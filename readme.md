# my custom stuff for Yandex Station Street (mango)
###### main source for stuff: [hackalice.me](https://hackalice.me)

one of the few models that has a 32-bit system, so it requires some less popular stuff

## Кнопки

> notes/maind_reverse_engineering_notes.md - заметки шизофреника о безнадежных попытках найти способ rewire кнопку алисы

> <del>на старте оно запускает один огромный чертовый бинарник по нескольку раз. он отвечает за всю логику колонки, поэтому так просто это сделать нельзя
больше почитать можно еще [тут](https://github.com/Marker284/yandex-station-extended/blob/12278fb5bd560cc72d4815e2adbb4163ebbee469/docs/internals/architecture.md#maind)</del>

был навайбслопен кастомный инициализатор кнопок, тепеьр все работает в режиме бункера/без запуска maind

запуск `scripts/install-buttonsd.sh` должно все сделать

> [!NOTE]
> Я это делал под себя, поэтому управление настроено для использования со `spotiya`, если вы хотите что то другое - милости прошу переписывать скрипты в `scripts/buttons` под себя :3

## contents
#### bin
binaries compiled for station
#### scripts
custom scripts (duh)
#### system_files
copied from device
