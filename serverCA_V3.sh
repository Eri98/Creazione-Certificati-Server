#!/bin/bash 

#===============================================================================
#          Ergis Kocumi v.3.0 of the script
#          FILE: serverCA_V3.sh
#
#         USAGE: ./serverCA_V3.sh 
# This script is used for creating:
# 1. the key for the server
# 2. The CSR for the server with the key of 1. 
# 3. Creating the X509 DIGITAL CERTIFICATE for the server signed by the CAkey
#    that is created with the script "genSSL_V3.sh"
#===============================================================================



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


genServer_Certs()
{
    #STEP 1: creating che key for the server
    info "Generate Private Key for the Server"
    #COMAND: 
    openssl genrsa -out server.key.pem 4096 2>/dev/null && echo -n "[DONE]" || fatal "Unable to Generate Private Key for the Server"

    #STEP 2: generate the CSR for server with the key at step 1
    info "Generate CSR for server certificate"
    #COMAND:
    openssl req -new -key server.key.pem -out server.csr   || fatal "unable to generate CSR for the server"
## MI SI BLOCCA QUI e mi da il FATAL con l'errore

    #STEP 3: verify the csr
    info "Verify the CSR created before"
    #COMAND:
        openssl req -in server.csr -noout -text

#STEP 6: creating the CERTIFICATE
    info "Generate a digital certificate x509 for the client/server"
    #COMAND: 
    openssl x509 -req -in server.csr -extfile v3.ext -CA CAcert.pem -CAkey CAkey.pem -CAcreateserial -out srv_mydomain_com.crt -days 500 -sha256

#STEP 7: verify the certificate created before
    info "verify the certificate created before"
    #COMAND: 
    openssl x509 -in srv_mydomain_com.crt -text -noout


    



}

## MAIN START ##
genServer_Certs
