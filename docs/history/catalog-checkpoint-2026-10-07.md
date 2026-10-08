# Checkpoint — catálogo e seleção local — 2026-10-07

## Confirmado no aparelho até agora

- Motor CSpot portado para ARMv7/iOS 9, com áudio pelo AudioQueue.
- Reprodução real após pareamento pelo Spotify Connect.
- Interface Now Playing, controles locais de pausa/retomada e troca de faixa funcionando após a correção de serialização.
- Reprodução com tela apagada e bloqueio funcionando na versão anterior a este patch.
- QR de autorização exibido no iPad, troca OAuth no iPad e credenciais reutilizáveis gravadas/lidas no Keychain.
- Login AP por OAuth e por credenciais reutilizáveis em conexão nova testados.

Esses resultados não confirmam reprodução independente depois de fechar e reabrir. Até agora a reprodução observada foi iniciada por outro dispositivo. Login AP aceito e estado CONNECTED não comprovam token de reprodução válido nem áudio saindo.

## Adicionado neste patch, aguardando teste no dispositivo

A tela Músicas consulta `GET https://api.spotify.com/v1/search`, com `type=track`, `limit=10` e a busca escapada. Usa um token obtido pelo AccessKeyFetcher da sessão CSpot atual. Não precisa de um player rodando no Mac: a requisição, a decodificação e o áudio executam no iPad.

A busca ocorre em uma thread separada. A interface apenas enfileira a seleção; o motor carrega a URI na mesma thread que processa os comandos de playback. Resultados de uma sessão encerrada são descartados. A seleção monta um comando LOAD e reutiliza o caminho existente de TrackQueue/TrackPlayer. A fila contém **uma faixa selecionada**; os resultados da busca não formam uma playlist nem uma fila automática. Escolha outra faixa em Músicas ao terminar.

Há tratamento de HTTP 401/403, respostas inválidas, limite de tamanho e HTTP 429 com espera. Não são gravados tokens, URLs de autorização nem códigos de callback no catálogo. A aceitação do token dessa sessão pela API pública continua sendo uma hipótese a verificar no aparelho.

Documentação do endpoint: https://developer.spotify.com/documentation/web-api/reference/search

## Teste obrigatório agora

1. Feche completamente o app no iPad. Remova qualquer marcador `cspot-use-connect-pairing` antigo. Não selecione CSpot no iPhone durante este teste.
2. Reabra iPad2MediaPlayer e aguarde CONNECTED pela sessão salva.
3. Toque em Músicas. A busca inicial deve exibir faixas reais. Se falhar, registre o texto na tela e `CATALOG: HTTP=...` / `PLAYBACK AUTH: ...`.
4. Toque em uma faixa. Confira título atualizado, progresso e áudio audível no iPad.
5. Pause e retome no iPad. Escolha outra faixa pela tela Músicas durante a reprodução.
6. Bloqueie manualmente; teste também o bloqueio automático. Confirme áudio contínuo por pelo menos um minuto.
7. Feche e reabra novamente, escolha uma faixa diferente e confirme reprodução sem parear nem selecionar o iPad no telefone.

Se o catálogo carregar mas a faixa não tocar, são etapas diferentes: a busca funcionou, mas a reprodução ainda precisa de diagnóstico. Se a API responder 401/403, precisamos resolver a autorização da API; não repetir buscas continuamente nem tratar CONNECTED como sucesso de playback.

Coleta de diagnóstico sem URLs de áudio nem tokens:

```sh
ssh -o HostKeyAlgorithms=+ssh-rsa root@<ipad-ip> \
  'cat /var/mobile/Documents/cspot-app.log' |
  grep -E 'APP:|AUTH:|CATALOG:|PLAYBACK AUTH:|Track failed|Load frame|Track name|AUDIO:' |
  tail -100
```

## Próximos marcos

- Confirmar o teste completo acima com sessão salva de origem Connect.
- Resolver o caminho de reprodução das credenciais de origem OAuth: o teste anterior de login5 retornou HTTP 200 com erro 1; não considerar esse caminho concluído.
- Implementar fila local, playlists/biblioteca, busca paginada e recuperação visível de falhas.
- Construir o relay HTTPS da autorização para eliminar o console no onboarding.
- Antes de distribuir: fixar versões e revisões, consolidar patches e normalização do SDK, reproduzir o build a partir de checkout limpo, verificar assinatura/entitlements e instalação, guardar avisos de licença e executar regressões no aparelho. Distribuição atual é experimental para dispositivo com jailbreak; nenhum caminho de App Store foi validado.
