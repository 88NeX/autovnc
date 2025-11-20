# autovnc

```
git clone https://github.com/88NeX/autovnc.git
cd autovnc
sed -i 's/^VNC_PASSWD=.*/VNC_PASSWD="Меняем пароль в кавычках на стандартный пароль для пользователя"/' ~/autovnc/autovnc.sh
chmod +x autovnc.sh
sudo ./autovnc.sh
```
После перезагрузки
```
x11vnc -storepasswd ~/.vnc/passwd
```
Дважды вводим пароль и принимаем запись
