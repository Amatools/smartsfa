# Firebase Auth - Codigos de erro no login

Este manual serve para interpretar os erros exibidos nas telas de login do SmartSFA.

## Formato exibido na tela

- Codigo: `firebase_auth_exception_code`
- Mensagem: descricao humana do problema

## Codigos mais comuns no login Google

### `operation-not-allowed`

Significado:

- o provedor Google nao esta habilitado no Firebase Authentication.

O que fazer:

- abrir Firebase Console > Authentication > Sign-in method;
- habilitar Google;
- salvar a configuracao.

### `unauthorized-domain`

Significado:

- o dominio atual nao esta liberado no Firebase Authentication.

O que fazer:

- abrir Firebase Console > Authentication > Settings > Authorized domains;
- adicionar o dominio usado no ambiente web;
- testar novamente.

### `popup-blocked`

Significado:

- o navegador bloqueou a janela de login.

O que fazer:

- liberar pop-ups para o dominio;
- tentar novamente;
- se necessario, usar outra janela ou aba sem bloqueio.

### `popup-closed-by-user`

Significado:

- o usuario fechou o popup antes de concluir o login.

O que fazer:

- repetir o login e concluir a confirmacao no Google.

### `permission-denied`

Significado:

- o Firebase recusou a operacao; no web, isso pode aparecer quando a API key do projeto foi suspensa, bloqueada ou o projeto esta com restricao de acesso.

O que fazer:

- conferir se o app esta apontando para o projeto correto;
- verificar se o Firebase Auth esta habilitado;
- verificar restricoes da API key no Google Cloud Console;
- revisar billing e status do projeto, se aplicavel;
- tentar novamente apos corrigir a configuracao.

## Codigos comuns no login por e-mail/senha

### `invalid-email`

Significado:

- o e-mail informado nao tem formato valido.

### `user-disabled`

Significado:

- a conta foi desabilitada no Firebase Auth.

### `user-not-found`

Significado:

- nao existe usuario cadastrado para aquele e-mail.

### `wrong-password`

Significado:

- a senha informada nao confere com a conta.

### `invalid-credential`

Significado:

- as credenciais sao invalidas ou expiraram.

## Observacoes operacionais

- O login web depende de dominio autorizado no Firebase.
- Se o erro nao tiver codigo conhecido, a tela deve exibir o codigo bruto retornado pelo Firebase.
- Quando o codigo aparecer como `unexpected`, normalmente o problema esta no navegador, rede ou configuracao de ambiente.
- Quando aparecer `permission-denied` com texto sobre `consumer-api-key`, o problema tende a ser de projeto/API key suspensa, nao da tela de login.