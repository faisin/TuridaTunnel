BIBlack='\033[1;90m'      # Black
BIRed='\033[1;91m'        # Red
BIGreen='\033[1;92m'      # Green
BIYellow='\033[1;93m'     # Yellow
BIBlue='\033[1;94m'       # Blue
BIPurple='\033[1;95m'     # Purple
BICyan='\033[1;96m'       # Cyan
BIWhite='\033[1;97m'      # White
UWhite='\033[4;37m'       # White
On_IPurple='\033[0;105m'  #
On_IRed='\033[0;101m'
IBlack='\033[0;90m'       # Black
IRed='\033[0;91m'         # Red
IGreen='\033[0;92m'       # Green
IYellow='\033[0;93m'      # Yellow
IBlue='\033[0;94m'        # Blue
IPurple='\033[0;95m'      # Purple
ICyan='\033[0;96m'        # Cyan
IWhite='\033[0;97m'       # White
NC='\e[0m'

# // Export Color & Information
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[0;33m'
export BLUE='\033[0;34m'
export PURPLE='\033[0;35m'
export CYAN='\033[0;36m'
export LIGHT='\033[0;37m'
export NC='\033[0m'

# // Export Banner Status Information
export EROR="[${RED} EROR ${NC}]"
export INFO="[${YELLOW} INFO ${NC}]"
export OKEY="[${GREEN} OKEY ${NC}]"
export PENDING="[${YELLOW} PENDING ${NC}]"
export SEND="[${YELLOW} SEND ${NC}]"
export RECEIVE="[${YELLOW} RECEIVE ${NC}]"

# // Export Align
export BOLD="\e[1m"
export WARNING="${RED}\e[5m"
export UNDERLINE="\e[4m"

# // Exporting URL Host
export Server_URL="raw.githubusercontent.com/faisin/turidatunnel/main/test"
export Server1_URL="raw.githubusercontent.com/faisin/turidatunnel/main/limit"
export Server_Port="443"
export Server_IP="underfined"
export Script_Mode="Stable"
export Auther=".geovpn"

# // Root Checking
if [ "${EUID}" -ne 0 ]; then
		echo -e "${EROR} Please Run This Script As Root User !"
		exit 1
fi

# // Exporting IP Address
export IP=$( curl -s https://ipinfo.io/ip/ )

# // Exporting Network Interface
export NETWORK_IFACE="$(ip route show to default | awk '{print $5}')"

# // Clear
clear
clear && clear && clear
clear;clear;clear
ssh="$(systemctl is-active ssh.service 2>/dev/null || true)"
if [[ "$ssh" == active ]]; then ressh="${green}ON${NC}"; else ressh="${red}OFF${NC}"; fi
sshstunel="inactive"; resst="${red}OFF${NC}"
sshws="$(systemctl is-active turidatunnel-ssh-ws.service 2>/dev/null || true)"; if [[ "$sshws" == active ]]; then ressshws="${green}ON${NC}"; else ressshws="${red}OFF${NC}"; fi
ngx="$(systemctl is-active nginx.service 2>/dev/null || true)"
if [[ "$ngx" == active ]]; then resngx="${green}ON${NC}"; else resngx="${red}OFF${NC}"; fi
dbr="$(systemctl is-active turidatunnel-dropbear.service 2>/dev/null || true)"
if [[ "$dbr" == active ]]; then resdbr="${green}ON${NC}"; else resdbr="${red}OFF${NC}"; fi
v2r="$(systemctl is-active xray.service 2>/dev/null || true)"
if [[ "$v2r" == active ]]; then resv2r="${green}ON${NC}"; else resv2r="${red}OFF${NC}"; fi
hpx="$(systemctl is-active haproxy.service 2>/dev/null || true)"
if [[ "$hpx" == active ]]; then reshpx="${green}ON${NC}"; else reshpx="${red}OFF${NC}"; fi
function addhost(){
clear
echo -e "\033[0;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
echo ""
read -rp "Domain/Host: " -e host
echo ""
if [ -z $host ]; then
echo "????"
echo -e "\033[0;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
read -n 1 -s -r -p "Press any key to back on menu"
menu
else
rm -fr /etc/xray/domain
echo "$host" > /etc/turidatunnel/domain
echo "IP=$host" > /var/lib/scrz-prem/ipvps.conf
echo "$host" > /etc/xray/domain
echo -e "\033[0;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
echo "Dont forget to renew gen-ssl"
echo ""
read -n 1 -s -r -p "Press any key to back on menu"
menu
fi
}
function genssl(){
  local domain
  domain="$(head -n1 /etc/turidatunnel/domain 2>/dev/null || head -n1 /etc/xray/domain)"
  if [[ -z "$domain" ]]; then echo "Domain belum diatur."; return 1; fi
  if ! certbot certonly --webroot -w /home/vps/public_html --non-interactive --agree-tos --register-unsafely-without-email -d "$domain"; then
    echo "Penerbitan sertifikat gagal. Pastikan DNS dan port 80 benar."; return 1
  fi
  install -m 0644 "/etc/letsencrypt/live/$domain/fullchain.pem" /etc/xray/xray.crt
  install -m 0640 "/etc/letsencrypt/live/$domain/privkey.pem" /etc/xray/xray.key
  chown root:www-data /etc/xray/xray.key
  systemctl reload nginx
  echo "Sertifikat TLS diperbarui tanpa menghentikan Nginx/HAProxy."
  read -rp 'Tekan Enter untuk kembali...' _
  menu
}
export sem="public"
# Variabel pak tidak digunakan; jangan membaca /home/.ver yang tidak dibuat installer.
IPVPS=$(curl -s ipinfo.io/ip )
ISPVPS=$( curl -s ipinfo.io/org )
clear
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m${NC}"
echo -e "\E[44;1;39m                   ⇱ SERVER INFORMATION ⇲                      \E[0m"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m${NC}"
echo -e "${BICyan} "                                                                      
echo -e "${BICyan} ⇲  ${BICyan}Use Core        :  ${BIYellow}FREE TUNNELING PTOJECT"    
echo -e "${BICyan} ⇲  ${BICyan}Current Domain  :  ${BIYellow}$(cat /etc/xray/domain)${NC}" 
echo -e "${BICyan} ⇲  ${BICyan}IP-VPS          :  ${BIYellow}$IPVPS${NC}"                  
echo -e "${BICyan} ⇲  ${BICyan}ISP-VPS         :  ${BIYellow}$ISPVPS${NC}"                 
echo -e "${BICyan} "
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m${NC}"
echo -e "\E[44;1;39m                    ⇱ STATUS SERVICE ⇲                        \E[0m"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m${NC}"
echo -e ""
echo -e "     ${BICyan} SSH ${NC}: $ressh"" ${BICyan} NGINX ${NC}: $resngx"" ${BICyan}  XRAY ${NC}: $resv2r"" ${BICyan} HAPROXY ${NC}: $reshpx"" ${BICyan} TROJAN ${NC}: $resv2r"
echo -e "     ${BICyan}          DROPBEAR ${NC}: $resdbr" "${BICyan} SSH-WS ${NC}: $ressshws"
echo -e ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m${NC}"
echo -e "\E[44;1;39m                     ⇱ MENU SERVICE ⇲                         \E[0m"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m${NC}"
echo -e ""
echo -e " ${BICyan}[${BIWhite}01${BICyan}]${RED} •${NC} ${CYAN}SSH MENU        $NC  ${BICyan}[${BIWhite}12${BICyan}]${RED} • ${NC}${CYAN}GEN-SSL / CERTV $NC"
echo -e " ${BICyan}[${BIWhite}02${BICyan}]${RED} •${NC} ${CYAN}VMESS MENU      $NC  ${BICyan}[${BIWhite}13${BICyan}]${RED} • ${NC}${CYAN}BANNER CHAGE $NC"
echo -e " ${BICyan}[${BIWhite}03${BICyan}]${RED} •${NC} ${CYAN}VLESS MENU      $NC  ${BICyan}[${BIWhite}14${BICyan}]${RED} • ${NC}${CYAN}CEK RUNNING SERVICE $NC"
echo -e " ${BICyan}[${BIWhite}04${BICyan}]${RED} •${NC} ${CYAN}TROJAN MENU     $NC  ${BICyan}[${BIWhite}15${BICyan}]${RED} • ${NC}${CYAN}CEK TRAFIC $NC"
echo -e " ${BICyan}[${BIWhite}05${BICyan}]${RED} •${NC} ${CYAN}S-SOCK MENU     $NC  ${BICyan}[${BIWhite}16${BICyan}]${RED} • ${NC}${CYAN}SPEEDTEDT  $NC"
echo -e " ${BICyan}[${BIWhite}06${BICyan}]${RED} •${NC} ${CYAN}TENDANG         $NC  ${BICyan}[${BIWhite}17${BICyan}]${RED} • ${NC}${CYAN}CEK BANDWIDTH USE $NC"
echo -e " ${BICyan}[${BIWhite}07${BICyan}]${RED} •${NC} ${CYAN}AUTO REBOOT     $NC  ${BICyan}[${BIWhite}18${BICyan}]${RED} • ${NC}${CYAN}LIMMIT SPEED $NC"
echo -e " ${BICyan}[${BIWhite}08${BICyan}]${RED} •${NC} ${CYAN}REBOOT          $NC  ${BICyan}[${BIWhite}19${BICyan}]${RED} • ${NC}${CYAN}WEBMIN $NC"
echo -e " ${BICyan}[${BIWhite}09${BICyan}]${RED} •${NC} ${CYAN}RESTART SERVICE $NC  ${BICyan}[${BIWhite}20${BICyan}]${RED} • ${NC}${CYAN}SCRIPT INFO $NC"
echo -e " ${BICyan}[${BIWhite}10${BICyan}]${RED} •${NC} ${CYAN}BACKUP MENU     $NC  ${BICyan}[${BIWhite}21${BICyan}]${RED} • ${NC}${CYAN}CLEAR LOG $NC"
echo -e " ${BICyan}[${BIWhite}11${BICyan}]${RED} •${NC} ${CYAN}ADD HOST        $NC  ${BICyan}[${BIWhite}22${BICyan}]${RED} • ${NC}${CYAN}FIX MISSING POINTING $NC"
echo -e " ${BICyan}[${BIWhite} X ${BICyan}] TYPE X FOR EXIT ${BICyan}${BIYellow}${BICyan}${NC}"  
echo -e " ${RED}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m${NC}"
echo -e "\E[44;1;39m                ⇱ FREE TUNNELING PROJECT ⇲                    \E[0m"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m${NC}"
echo
read -p " Select menu : " opt
echo -e ""
case $opt in
1) clear ; menu-ssh ;;
2) clear ; menu-vmess ;;
3) clear ; menu-vless ;;
4) clear ; menu-trojan ;;
5) clear ; menu-ss ;;
6) clear ; tendang ;;
7) clear ; autoreboot ;;
8) clear ; reboot ;;
9) clear ; restart ;;
10) clear ; menu-bckp ;;
11) clear ; addhost ;;
12) clear ; genssl ;;
13) clear ; nano /etc/issue.net ;;
14) clear ; running ;;
15) clear ; cek-trafik ;;
16) clear ; cek-speed ;;
17) clear ; cek-bandwidth ;;
#18) clear ; cek-ram ;;
18) clear ; limit-speed ;;
19) clear ; wbm ;;
20) clear ; cat /root/log-install.txt ;;
21) clear ; clearlog ;;
#99) clear ; update ;;
22) clear ; bash /opt/turidatunnel/cf.sh ;;

0) clear ; menu ;;
x) exit ;;
*) echo -e "" ; echo "Press any key to back exit" ; sleep 1 ; exit ;;
esac
