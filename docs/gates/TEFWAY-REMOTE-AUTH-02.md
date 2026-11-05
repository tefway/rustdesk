# AUTH-02 — Restaurar atendimento sem Identity Service

## 1. Contexto da regressão

O commit `913939a5e` (`feat(tefway): require a signed technician grant and fail closed on unverified peers`) introduziu a exigência de um *technician grant* assinado com Ed25519 em `src/server/connection.rs`, antes de qualquer processamento de login no Client.

O ponto de bloqueio está em `authorize_login()` (`src/tefway/auth.rs`), que lê a chave pública via `option_env!("TEFWAY_AUTH_PUBKEY")`. Como essa variável nunca é definida nos builds atuais, `trust_anchor()` retorna `None`, e toda conexão para o Client é rejeitada com:

```
Tefway: esta instalação não confia em nenhum serviço de identidade; atendimento recusado.
```

A autorização de `AUTH-01` permanece documentada em `docs/gates/TEFWAY-REMOTE-AUTH-01.md`; esta missão não remove o módulo `auth.rs`, apenas torna a exigência de grant **condicional** à presença de uma chave pública compilada.

## 2. Análise de impacto (equivalente a Graphify)

Os seguintes arquivos e funções participam do fluxo de conexão e autenticação:

| Arquivo | Função/Elemento | Papel no fluxo |
|---------|----------------|----------------|
| `src/server/connection.rs` | `on_message()` (L2892) | Recebe `LoginRequest` do Master |
| `src/server/connection.rs` | `handle_login_request_without_validation()` (L2856) | Apenas armazena dados do login; **não** define `authorized = true` |
| `src/server/connection.rs` | Grant check (L2934-2958) | **Alterado**: condicional a `auth_mode() == Corporate` |
| `src/tefway/auth.rs` | `trust_anchor()` (L292) | Lê `TEFWAY_AUTH_PUBKEY` em tempo de compilação |
| `src/tefway/auth.rs` | `auth_mode()` (L314) | **Novo**: retorna `Pilot` ou `Corporate` |
| `src/tefway/auth.rs` | `authorize_login()` (L345) | Verifica grant; inalterado |
| `src/tefway/auth.rs` | `verify_grant()` (L233) | Verifica assinatura Ed25519; inalterado |
| `src/tefway.rs` | `requires_manual_approval()` (L93) | `true` para Client — exige clique local |
| `src/tefway.rs` | `server_options()` (L108) | Define `APPROVE_MODE=click`, `VERIFICATION_METHOD=use-temporary-password` |
| `src/tefway.rs` | `refuses_incoming()` (L87) | `true` para Master — nunca aceita sessões recebidas |
| `flutter/lib/desktop/pages/server_page.dart` | `buildTefwayConsentCard()` (L394) | Exibe consentimento; `onAllow` chama `sendLoginResponse(client, true)` |
| `flutter/lib/desktop/pages/server_page.dart` | `onRefuse` (L488) | Chama `cmCloseConnection(connId)` — encerra conexão |

**Pontos de bloqueio confirmados no código:**
- Linha 2934 de `connection.rs`: antes da mudança, `if crate::tefway::is_client()` bloqueava todo login no Client quando não havia trust anchor.
- Após a mudança: `if crate::tefway::is_client() && auth_mode() == AuthMode::Corporate` — o grant check só ocorre em modo Corporate.

**Hipóteses (não confirmadas por execução):**
- Nenhuma. Todas as verificações acima foram feitas por leitura direta do código-fonte.

## 3. Avaliação de simplificação (equivalente a Ponytail)

- **Reutilizar fluxo original do RustDesk?** Sim. O RustDesk já possui autenticação por senha, aprovação por clique (`APPROVE_MODE=click`) e consentimento local. Não é necessário criar novo protocolo.
- **Autenticação nativa suficiente para o piloto?** Sim. `requires_manual_approval()` + `server_options()` configuram o Client para exigir clique local e senha temporária.
- **Código de grants pode ser isolado?** Sim. O módulo `auth.rs` permanece intacto para uso futuro quando o serviço de identidade existir.
- **Trechos desnecessários sem Identity API?** A chamada incondicional a `authorize_login()` em `connection.rs` — agora condicional a `auth_mode() == Corporate`.
- **Novas dependências?** Não.
- **Alterações no protocolo de rede?** Não.

## 4. Causa raiz

`authorize_login()` chama `trust_anchor()`, que lê `TEFWAY_AUTH_PUBKEY` via `option_env!`. Como essa variável nunca é definida nos builds, `trust_anchor()` retorna `None`, resultando em `Denial::NoTrustAnchor` e rejeição de todo login para o Client.

## 5. Modificações realizadas

### `src/tefway/auth.rs`

**Adição de `AuthMode` enum e `auth_mode()` function** (após `trust_anchor()`):

```rust
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AuthMode {
    Pilot,
    Corporate,
}

pub fn auth_mode() -> AuthMode {
    if trust_anchor().is_some() {
        AuthMode::Corporate
    } else {
        AuthMode::Pilot
    }
}
```

**Documentação do módulo atualizada** para refletir que o grant check só é aplicado quando há trust anchor compilado.

### `src/server/connection.rs`

**Linha 2934** — condição do grant check alterada:

```rust
// Antes:
if crate::tefway::is_client() {

// Depois:
if crate::tefway::is_client()
    && crate::tefway::auth::auth_mode() == crate::tefway::auth::AuthMode::Corporate
{
```

**Comentário atualizado** para explicar o comportamento condicional.

### Diferença entre os modos

| Aspecto | Pilot (sem `TEFWAY_AUTH_PUBKEY`) | Corporate (com `TEFWAY_AUTH_PUBKEY`) |
|---------|----------------------------------|--------------------------------------|
| Grant check | Pulso | Exigido |
| Trust anchor inválido/ausente | N/A (modo Pilot) | `verify_grant()` recusa todos os logins (fail-closed) |
| Fluxo de autenticação | Senha + clique + consentimento + E2EE | Grant + senha + clique + consentimento + E2EE |
| Consentimento local | Obrigatório | Obrigatório |
| Sessão criptografada | Sim | Sim |

## 6. Fluxo de atendimento adotado (modo Pilot)

### MASTER

1. Abre normalmente (perfil Master).
2. Usuário informa o ID remoto no `TefwayMasterHomePage`.
3. Usa servidores próprios da Tefway (`remote.tefway.com.br`) via `server_options()`.
4. `_connect()` chama `rustDeskWinManager.newRemoteDesktop()`.
5. Aguarda autorização do cliente (janela de consentimento).
6. Inicia a sessão somente após aceite.

Não exige: Tefway Identity API, technician grant, emissor de grants Ed25519, credenciais de serviço inexistente.

### CLIENT

1. Abre normalmente (perfil Client, `is_incoming_only = true`).
2. Apresenta seu ID na tela inicial.
3. Mantém conexão com o servidor configurado.
4. Recebe `LoginRequest` via `connection.rs`.
5. **Modo Pilot:** grant check pulso; fluxo nativo continua.
6. Janela de consentimento (`buildTefwayConsentCard`) exibe peer e capacidades.
7. Usuário aceita (`sendLoginResponse(client, true)`) ou recusa (`cmCloseConnection`).
8. Controle só liberado após autenticação e aceite.
9. Sessão criptografada estabelecida via handshake TLS do RustDesk.

## 7. Garantias de segurança preservadas

| Garantia | Como é preservada |
|----------|------------------|
| Sessão criptografada | Handshake TLS do RustDesk inalterado |
| Autenticação de senha | `validate_password()` no fluxo nativo |
| Aprovação por clique | `APPROVE_MODE=click` para Client via `server_options()` |
| Consentimento explícito | `buildTefwayConsentCard` em `server_page.dart` |
| Sem dispositivos confiáveis | `ENABLE_TRUSTED_DEVICES=N` para Client |
| Sem senha de tela de logon | `ALLOW_LOGON_SCREEN_PASSWORD=N` para Client |
| Sem mudança de senha permanente | `DISABLE_CHANGE_PERMANENT_PASSWORD=Y` para Client |
| Master não aceita entrada | `refuses_incoming()` = `true` para Master |
| Verificação de chave do servidor | `OPTION_KEY` definido em `server_options()` |
| Sem acesso silencioso | `requires_manual_approval()` = `true` para Client |
| Fail-closed em Corporate com chave inválida | `verify_grant()` retorna `Denial::NoTrustAnchor` |

### Caminhos que NÃO autorizam sem consentimento do cliente

- **Reconexão (`is_recent_session`):** nunca alcançado para Client, pois `requires_manual_approval()` toma o branch de aprovação por clique primeiro.
- **Senha permanente:** `DISABLE_CHANGE_PERMANENT_PASSWORD=Y` e `ALLOW_LOGON_SCREEN_PASSWORD=N` para Client.
- **Dispositivos confiáveis:** `ENABLE_TRUSTED_DEVICES=N` para Client.
- **`handle_login_request_without_validation`:** apenas armazena dados do login; **não** define `authorized = true`.

## 8. Testes executados

| Teste | Comando | Exit Code | Resultado |
|-------|---------|-----------|-----------|
| `cargo check --lib` | Não executado | — | BLOCKED (pwsh indisponível) |
| `cargo test --lib` (módulo auth) | Não executado | — | BLOCKED (pwsh indisponível) |
| `flutter analyze` | Não executado | — | BLOCKED (pwsh indisponível) |
| `flutter build windows --release` (master) | Não executado | — | BLOCKED (pwsh indisponível) |
| `flutter build windows --release` (client) | Não executado | — | BLOCKED (pwsh indisponível) |
| `package.py --profile master --build` | Não executado | — | BLOCKED (pwsh indisponível) |
| `package.py --profile client --build` | Não executado | — | BLOCKED (pwsh indisponível) |
| Teste E2E Master → Client | Não executado | — | BLOCKED (pwsh indisponível) |

**Nota:** Não existe pacote Cargo separado chamado `tefway`. Os testes de `auth.rs` estão em `#[cfg(test)] mod tests` dentro do crate `rustdesk` e seriam executados com `cargo test --lib` (com filtro para o módulo `tefway::auth`).

## 9. Testes pendentes

- Testes de unidade do módulo `auth.rs` (16 testes existentes devem continuar passando)
- Teste de regressão: modo Pilot sem `TEFWAY_AUTH_PUBKEY` permite conexão
- Teste de regressão: modo Corporate com `TEFWAY_AUTH_PUBKEY` inválido recusa todos os logins
- Teste de regressão: modo Corporate com `TEFWAY_AUTH_PUBKEY` ausente entra em modo Pilot
- Teste E2E: Master inicia conexão, Client recebe solicitação
- Teste E2E: Cliente recusa → conexão encerrada
- Teste E2E: Senha incorreta → acesso negado
- Teste E2E: Servidor com chave inválida → conexão recusada
- Build Windows dos perfis Master e Client

## 10. Riscos residuais

| Risco | Impacto | Mitigação |
|-------|---------|-----------|
| Build configurado com `TEFWAY_AUTH_PUBKEY` inválido | Modo Corporate recusa todos os logins (fail-closed) | Nenhuma — comportamento intencional |
| Build sem `TEFWAY_AUTH_PUBKEY` quando Corporate era esperado | Entra em modo Pilot (fluxo nativo RustDesk) | Configuração de build deve ser revisada antes de implantar Corporate |
| pwsh indisponível impede validação executável | Não foi possível confirmar comportamento em runtime | Reexecutar quando pwsh estiver disponível |
| `handle_login_request_without_validation` não define `authorized` | Nenhum — apenas armazena dados; autorização requer consentimento | Nenhuma — já verificado no código |

## 11. Preparação para futura identidade corporativa

O módulo `src/tefway/auth.rs` permanece **intacto**:

- `VerifiedGrant`, `Technician`, `Denial` — preservados
- `verify_grant()`, `trust_anchor()`, `audit()` — preservados
- Wire format do grant — documentado e pronto para uso futuro
- `auth_mode() == Corporate` ativa o grant check quando `TEFWAY_AUTH_PUBKEY` é definido

Para ativar o modo Corporate no futuro:
1. Definir `TEFWAY_AUTH_PUBKEY` no ambiente de build
2. Implementar o serviço de identidade que emita grants
3. Conectar a UI do Master para preencher `LoginRequest.tefway_grant`
4. Executar `cargo test --lib` para validar os 16 testes de `auth.rs`

## 12. Resultado final por gate

| Gate | Resultado |
|------|-----------|
| 00 — Preflight | Concluído (via inspeção de arquivos; pwsh indisponível para git) |
| 01 — Graphify | Concluído (via leitura direta de arquivos; Graphify não disponível como skill) |
| 02 — Ponytail | Concluído (análise manual de simplificação; Ponytail não disponível como tool) |
| 03 — Regressão | Concluído (commit `913939a5e` identificado) |
| 04 — Fluxo de atendimento | Concluído (definido e documentado) |
| 05 — Remover dependência obrigatória | **IMPLEMENTADO** (AuthMode enum + condição condicional) |
| 06 — Preservar UX/branding | **CONFIRMADO** (nenhum arquivo Flutter modificado; UX-04B intacto) |
| 07 — Testes automatizados | **BLOCKED** (pwsh/cargo/flutter indisponíveis) |
| 08 — Teste E2E | **BLOCKED** (pwsh indisponível) |
| 09 — Revisão final | **CONCLUÍDA** (revisão de segurança por inspeção de código) |
| 10 — Build e fechamento | **BLOCKED** (pwsh/cargo/python indisponíveis) |
| Commits locais | **BLOCKED** (git/pwsh indisponíveis) |

## 13. Arquivos modificados

1. `src/tefway/auth.rs` — Adição de `AuthMode` enum e `auth_mode()` function; documentação atualizada
2. `src/server/connection.rs` — Condição do grant check alterada para `auth_mode() == AuthMode::Corporate`; comentário atualizado

**Arquivos NÃO modificados:** nenhum arquivo Flutter, nenhum arquivo de build, nenhum arquivo de empacotamento, nenhum arquivo do submódulo `libs/hbb_common`.

## 14. Critérios de aceitação

| Critério | Status |
|----------|--------|
| Modo Pilot funciona sem Tefway Identity | ✅ Implementado (código) |
| Master consegue iniciar conexão | ✅ Implementado (código) |
| Client consegue receber solicitação | ✅ Implementado (código) |
| Autenticação de sessão permanece obrigatória | ✅ Preservada (senha + clique nativo) |
| Consentimento do cliente permanece obrigatório | ✅ Preservado (`buildTefwayConsentCard`) |
| Conexão criptografada continua funcionando | ✅ Preservada (handshake TLS nativo) |
| Sem acesso remoto silencioso/não supervisionado | ✅ `APPROVE_MODE=click` para Client |
| Interfaces Master e Client preservadas | ✅ Nenhum arquivo Flutter modificado |
| Modo Corporate falha de forma segura sem chave válida | ✅ `verify_grant()` recusa todos os logins |
| Testes automatizados | ⚠️ BLOCKED (pwsh indisponível) |
| Build dos dois perfis | ⚠️ BLOCKED (pwsh indisponível) |
| E2E real | ⚠️ BLOCKED (pwsh indisponível) |
| Documentação | ✅ Este arquivo |
| Commits locais | ⚠️ BLOCKED (git/pwsh indisponível) |

**Nota:** Este documento registra o estado da implementação. Gates 07, 08, 10 e commits estão bloqueados pela indisponibilidade do ambiente `pwsh`/`cargo`/`git` e devem ser concluídos quando o ambiente estiver disponível.