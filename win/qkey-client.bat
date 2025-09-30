@echo off

rem net session >nul 2>&1
rem if %errorlevel% neq 0 (
rem     echo このバッチファイルは管理者権限で実行する必要があります。
rem     pause
rem     exit /b
rem )

setlocal

:: バッチファイルのディレクトリをカレントディレクトリとして設定
cd /d "%~dp0"

set RUST_LOG=debug
qkey.exe --server-ip 162.43.52.23 --server-port 8080

rem route delete 0.0.0.0
rem route add 0.0.0.0 mask 0.0.0.0 10.0.0.1 METRIC 50

rem route DELETE 0.0.0.0 MASK 0.0.0.0 192.168.0.1
rem route DELETE 10.0.0.26 MASK 255.255.255.255
rem route ADD 0.0.0.0 MASK 0.0.0.0 192.168.0.1 METRIC 100
rem route ADD 162.43.45.142 MASK 255.255.255.255 192.168.0.1 METRIC 100
rem netsh interface ip show route
rem netsh advfirewall reset
rem netsh advfirewall show allprofiles
rem netsh advfirewall firewall add rule name="Allow_QKEY_Client_UDP_8080" protocol=UDP dir=out remoteip=162.43.45.142 remoteport=8080 action=allow
rem netsh advfirewall firewall show rule name=Allow_QKEY_Client_Port
rem netsh advfirewall firewall delete rule name="Allow_QKEY_Client_Port"
rem netsh advfirewall firewall add rule name="Allow_DNS_Out" protocol=UDP dir=out localport=53 action=allow
rem netsh advfirewall firewall add rule name="Allow_DNS_In" protocol=UDP dir=in localport=53 action=allow
rem tracert 162.43.45.142
pause
endlocal
