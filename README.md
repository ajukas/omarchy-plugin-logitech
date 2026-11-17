# ajukas.logitech

Widget da barra do Omarchy para gerenciar os dispositivos Logitech: mouse, headset
e webcam. Inspirado no [Omalogi](https://github.com/elberacasa/omalogi), no
[Peripheral Battery](https://github.com/hlasensky/omarchy-peripheral-battery) e no
[EMEET PIXY](https://github.com/nille/omarchy-emeet-pixy).

- Clique esquerdo: abre o card com uma aba por dispositivo.
- Clique do meio: abre a prévia da câmera.
- O ícone fica em destaque quando a bateria do mouse ou do headset está baixa, e uma
  notificação é enviada uma vez quando ela cai abaixo de 10% (ajustável nas configurações do widget).

## O que cada aba faz

| Aba | Recursos | Depende de |
|---|---|---|
| Mouse | bateria (via kernel, `hidpp_battery`) | nada |
| | DPI e taxa de resposta | `solaar` |
| Headset | volume, mudo do microfone, tornar saída/entrada padrão (PipeWire) | nada |
| | bateria, sidetone, desligamento automático | `headsetcontrol` |
| Câmera | brilho, contraste, saturação, nitidez, ganho, zoom, foco, balanço de branco, exposição, anti-cintilação, prévia | `v4l-utils`, `mpv` |

Webcams perdem os ajustes ao serem desconectadas ou após reiniciar. Cada ajuste feito
no card é salvo em `~/.config/ajukas-logitech/camera.json` e reaplicado quando a câmera
aparece de novo (desligável nas configurações do widget). "Restaurar padrão" volta aos
valores de fábrica e apaga o perfil salvo.

Testado com G703 LIGHTSPEED, PRO X Wireless e C920 PRO.

A bateria do headset é lida pelo `headsetcontrol` no máximo uma vez a cada
(desligamento automático + 5 min), ou 30 min se o desligamento estiver desativado:
cada consulta conversa com o fone pelo rádio e conta como atividade, o que impediria
que ele desligasse sozinho. Entre as consultas o widget mostra a última leitura e
detecta o receptor pelo sysfs. Abrir o card força uma leitura nova.

## Dependências opcionais

```sh
sudo pacman -S solaar headsetcontrol
```

Os dois pacotes instalam regras udev que liberam o acesso aos dispositivos; depois de
instalar, desconecte e reconecte o receptor e o headset (ou reinicie).

## Instalação

```sh
ln -s ~/project/plugins/ajukas.logitech ~/.config/omarchy/plugins/ajukas.logitech
omarchy-shell shell rescanPlugins
omarchy plugin enable ajukas.logitech
```

Como o plugin é um link simbólico, edições aqui não recarregam sozinhas; rode
`omarchy restart shell` depois de alterar o código.

## Arquivos

- `BarWidget.qml`: ícone da barra, estado e fila de comandos.
- `LogiPanel.qml`: conteúdo do card (abas).
- `DeviceHeader.qml`, `SliderRow.qml`: componentes do card.
- `logi-helper.py`: faz todo o acesso aos dispositivos e responde em JSON
  (`./logi-helper.py status` para depurar).
