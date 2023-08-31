#!/bin/bash 

#===============================================================================
#
#          FILE: genSSL_V3.sh
#
#         USAGE: ./genSSL_V3.sh 




#variables ges here


#set flag here
XFOUND=0

# edit these below values to replace with yours
homedir=''
yourdomain=''
country=IT
state=Italy
locality=Genoa
organization="Hitachi"
organizationalunit="Automation"
san="IP.1=192.168.26.101"
# OS is declared and will be used in its next version
OS=$(egrep -io 'Redhat|centos|fedora|ubuntu' /etc/issue)





### function declarations ###

#function to print the info for evere step like "DEBUG"
info()
{
  printf '\n%s\t%s\t' "INFO" "$@"
}

#function for printing the error if it happens
fatal()
{
 printf '\n%s\t%s\n' "ERROR" "$@"
 exit 1
}





printCSR()
{
if [[ -e CAcert.pem ]] && [[ -e CAkey.pem ]]
then
echo -e "\n\n----------------------------CRT-----------------------------"
cat CAcert.pem
echo -e "\n----------------------------KEY-----------------------------"
cat CAkey.pem
echo -e "------------------------------------------------------------\n"
else
fatal "CSR or KEY generation failed !!"
fi
}


genCA_Certs()
{
    #STEP 1: creating che key for the CA to use for signign 
    info "Generate RootCA Private Key"
    #COMAND: 
    openssl genrsa -out CAkey.pem 4096 2>/dev/null && echo -n "[DONE]" || fatal "Unable to Generate RootCA Private key"

    #STEP 2: generatiche the ROOTCA certificate with the key at step 1
    info "Generate RootCA Certificate"
    #COMAND:
    openssl req -new -x509 -days 3650 -extensions v3_ca -key CAkey.pem -out CAcert.pem  && echo -n "[DONE]" || fatal "Unable to Generate RootCA Certificate"
## dopo aver aggiunto la riga di codice per segnalare un errore in caso >>  (((  2>/dev/null && echo -n "[DONE]" || fatal "Unable to Generate RootCA Certificate"))) 
## il programma non continua più a funzionare e non capisco perchè



}

### START MAIN ###



  parseSubject "$subj"
genCA_Certs

if [ $XFOUND -eq 0 ]
  then
    sleep 2
    printCSR
fi
