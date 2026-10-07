# Lista de músicas e seleção local no iPad

Este patch adiciona a tela **Músicas** ao iPad2MediaPlayer. A busca inicial é “Luiz Gonzaga”; você pode trocar por qualquer música ou artista. A tela solicita até dez faixas à API de busca do Spotify e mostra título, artista e álbum. Toque na linha para carregar a faixa no motor nativo do iPad. O botão de informação abre a página da faixa no Spotify.

Pré-requisitos: os patches de controles serializados, QR no dispositivo, diagnóstico do token de reprodução e recuperação por Connect devem estar aplicados. O instalador verifica os arquivos anteriores antes de escrever e guarda backups. Não contém um binário pré-compilado.

## Aplicar e compilar

No Mac, a partir do projeto:

```sh
cd ~/Projects/Personal/ipad2MediaPlayer
tar -xzf ~/Downloads/ipad2-catalog-picker.tar.gz
python3 ipad2-catalog-picker/apply.py "$PWD" --check &&
python3 ipad2-catalog-picker/apply.py "$PWD"
source native-player/build-venv/bin/activate
bash native-player/ios/auth/build-login-app.sh
```

Feche o app no iPad pelo seletor de aplicativos antes de reinstalar. Copie a pasta completa:

```sh
scp -r -O -o HostKeyAlgorithms=+ssh-rsa \
  native-player/ios/build/iPad2MediaPlayer.app \
  root@192.168.13.24:/Applications/ &&
ssh -o HostKeyAlgorithms=+ssh-rsa root@192.168.13.24 \
  'chown -R mobile:mobile /Applications/iPad2MediaPlayer.app && uicache'
```

O arquivo `native-player/ios/catalog/README.md` contém o checkpoint e o roteiro de validação. Não refaça o pareamento para testar: reabra o app, aguarde CONNECTED e toque em Músicas. Se houver um marcador antigo forçando o pareamento, remova apenas esse marcador antes de abrir o app:

```sh
ssh -o HostKeyAlgorithms=+ssh-rsa root@192.168.13.24 \
  'rm -f /var/mobile/Documents/cspot-use-connect-pairing'
```

## Verificação feita aqui

Passaram a verificação de sintaxe C++ do catálogo, da ponte, do carregamento e da integração com o motor; os testes da ponte existente de controles; os testes do catálogo com transporte simulado; e a codificação/decodificação nanopb real do comando local de carregamento. O teste confirma contexto, posição inicial, uma faixa na fila, padding do ID de 128 bits e rejeição de IDs inválidos. Também passaram os testes do instalador: preflight, aplicação, segunda aplicação sem mudanças e conflito sem escrita parcial.

A compilação Objective-C/UIKit e o teste com Spotify real dependem do seu Mac e do iPad. Ainda não confirmamos se o token emitido para esta sessão é aceito pela API pública de busca, nem reprodução após reiniciar sem novo pareamento. HTTP 401/403 é mostrado na tela e registrado sem imprimir o token.
