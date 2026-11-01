# Mapa Vivo — mapa da comunidade

Aplicativo Flutter para descobrir e compartilhar lugares na cidade onde você está. Usa mapas do OpenStreetMap sem exigir uma chave de API, centraliza o mapa na localização atual do dispositivo e permite adicionar pontos tocando em qualquer lugar do mapa.

## Mapa e localização

O mapa usa o `flutter_map` com os tiles do OpenStreetMap e o `geolocator` para obter a localização do dispositivo. Os tiles não exigem uma chave de API; para usar o app, crie ou entre em uma conta local neste aparelho/navegador. Ao abrir o mapa, permita o acesso à localização; o botão de mira centraliza o mapa novamente na sua posição. O mapa pode ser arrastado e ampliado normalmente. Para adicionar um ponto, toque no botão `+`, informe os dados e toque no local desejado.

O mapa deve permanecer com a atribuição visível a **© OpenStreetMap contributors**. Os tiles públicos do OpenStreetMap têm política de uso e não são um serviço offline ou de disponibilidade garantida; para uso comercial ou tráfego significativo, escolha um provedor de tiles apropriado ou hospede os próprios tiles. Na web, a localização depende da permissão do navegador e de um contexto seguro (`localhost` ou HTTPS).

O projeto mantém `path_provider_foundation` em uma versão sem o hook nativo `objective_c`, que pode falhar no Windows quando o Flutter SDK ou o cache do Pub está em um caminho com espaços.

## Executar no Windows

```sh
cd "C:\Code\Faculdade\5_período\PDM\Trabalho Final\MapaVivo"
flutter pub get
flutter run -d chrome
```

Para executar no Android, inicie um emulador ou conecte um aparelho com depuração USB e use `flutter run`.

## Contas locais e dados

O app permite criar vários perfis locais e entrar/sair entre eles. As contas, os pontos, a autoria, as avaliações e as mensagens são salvos no armazenamento local do Android ou do navegador. Senhas não são gravadas em texto puro: o app armazena somente um hash PBKDF2-HMAC-SHA-256 com salt individual.

Esta versão é **somente local**. Os perfis e pontos não são compartilhados com outros usuários ou sincronizados entre aparelhos; no navegador, os dados ficam apenas naquele navegador e origem. A identidade e os dados podem ser alterados por alguém com acesso ao aparelho ou às ferramentas do navegador. O controle de exclusão por autoria é uma regra da interface local, não uma autorização confiável de servidor. Para uma comunidade real com contas verificadas, dados compartilhados e direitos de exclusão protegidos, será necessário integrar um backend com autenticação e autorização no servidor.
