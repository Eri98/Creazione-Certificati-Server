#your Variables go here
SCRIPT=${0##/}
WRITEFORMAT=table
CONFIG=0
DIR=0
LOGLEVEL=info
SSLCMD=$(which openssl) #COMMAND FOR OPEN AN SSL
JQ=$(which jq)
EXT=crt
HEADER="certificate;common_name;issued_by;serial;time_before_expire" #HEADER OF THE TABLE THAT IS GOING TO PRINT
SSLCERTIFICATEMETRICNAME=ssl_certificate_time_to_expire
SSLCERTIFICATESCANNED=ssl_certificates_scanned_total
SSLCERTIFICATEEXPIRED=ssl_certificates_expired_total
SCANNED=0
EXPIRED=0
OUTFILE=''
# functions here
usage()
{
cat <<EOF
  USAGE: $SCRIPT -[cdewolh]"
  DESCRIPTION: This script predicts and prints the expiring SSL certificates based on the end date.
  OPTIONS:
  -c|   sets the value for configuration file which has server:port or host:port details.
  -d|   sets the value of directory containing the certificate files in crt or pem format.
  -e|   sets the value of certificate extention [crt, pem], default: crt
  -w|   sets the value for output format of the script [table, csv, json, prometheus], default: table
  -o|   write output to a file.
  -l|   sets the log level [info, debug, error, warn], default: info
  -h|   prints this help and exit.
EOF
exit 1
}

error()
{
  >&2 printf '\n%s: %6s\n' "ERROR" "$@"
  exit 1
}

warn()
{
  >&2 printf '\n%s: %6s\n\n' "WARN" "$@"
}

log()
{
  local LEVEL=$LOGLEVEL
  local SEVERITY=$1
  local MESSAGE=$2
  if [[ "${LEVEL}" = "${SEVERITY}" ]]; then
  # check if loglevel is same as severity or one of the valid log levels.
    case $SEVERITY in
      info|debug ) printf '\n%s: %6s\n' "${SEVERITY}" "$MESSAGE";;
      * ) error "invalid log level $LOGLEVEL";;
    esac
  fi
}

#you have to modify with -w to set this print_style
printCSV() 
{
  local ARGS=$@
  i=0
  if [[ ${#ARGS} -ne 0 ]]; then
    #statements
    printf '%s\n' $HEADER | awk -F";" 'BEGIN{OFS=","};{print $1,$2,$3,$4,$5}'
    printf '%s\n' ${ARGS}  | \
      sed 's/|/ /g;s/\;/,/g' | \
      sort -t',' -g -k5
  fi
}

#default
printTable()
{
  local ARGS=$@
  local LINEBREAK="---------------------------------------------------------------------------------------------------------------------------------------------------------------"
  i=0
  if [[ ${#ARGS} -ne 0 ]]; then
    #statements
    printf '%s\n' $LINEBREAK
    printf '%70s\n' "List of expiring SSL certificates"
    printf '%s\n' $LINEBREAK
    printf '%s\n%s\n' ${HEADER^^} ${ARGS}  | \
      sed 's/|/ /g' | \
      sort -t';' -g -k5 | \
      column -s';' -t     | \
      awk '{printf "%s\n", $0}'
    printf '%s\n' $LINEBREAK
  fi
}

#you have to modify with -w to set this print_style
printJSON()
{
  local ARGS=$@
  local VALUE=''
  if [[ ${#ARGS} -ne 0 ]]; then
    count=1
    printf '%s' "{ \"items\": [ "
      for VALUE in ${ARGS}; do
        VALUE=(${VALUE//;/ })
        printf '%s' "{ \"${VALUE[0]}\": { \"commonname\": \"${VALUE[1]//|/ }\", \"issuer\": \"${VALUE[2]//|/ }\", \"serial\": \"${VALUE[3]}\", \"days\": ${VALUE[4]} } }, "
      done| sed -r 's/(.*), /\1/'
    printf '%s' " ] }"
  fi
}

#you have to modify with -w to set this print_style
printPrometheus()
{
  local ARGS="$1"
  local SCANNEDCERTS=$2
  local EXPIREDCERTS=$3
  local VALUE=''

  printf '%s\n' "# HELP $SSLCERTIFICATEMETRICNAME ssl certificate expiration time in days"
  printf '%s\n' "# TYPE $SSLCERTIFICATEMETRICNAME GAUGE"
  for VALUE in ${ARGS}; do
    VALUE=(${VALUE//;/ })
    # ignore putting filename in prometheus metrics
    printf '%s %.2f\n' "$SSLCERTIFICATEMETRICNAME{commonname=\"${VALUE[1]//|/ }\",issuer=\"${VALUE[2]//|/ }\",serial=\"${VALUE[3]}\"}" ${VALUE[4]}
  done
  printf '%s\n' "# HELP $SSLCERTIFICATESCANNED total ssl certificates scanned"
  printf '%s\n' "# TYPE $SSLCERTIFICATESCANNED COUNTER"
  printf '%s %d\n' "$SSLCERTIFICATESCANNED" $SCANNEDCERTS

  printf '%s\n' "# HELP $SSLCERTIFICATEEXPIRED total ssl certificates expired"
  printf '%s\n' "# TYPE $SSLCERTIFICATEEXPIRED COUNTER"
  printf '%s %d\n' "$SSLCERTIFICATEEXPIRED" $EXPIREDCERTS
}

printOutput()
{
  local ARGS=$@
  case $WRITEFORMAT in
    table) printTable "${ARGS}";;
    csv) printCSV "${ARGS}";;
    json) if [[ "x${JQ}" = "x" ]]; then
        warn "to pretty print json, install jq"
        printJSON "${ARGS}"
      else
        printJSON "${ARGS}"|${JQ}
      fi;;
    prometheus) EXT=prom; printPrometheus "${ARGS}"  $SCANNED $EXPIRED;;
    *) error "$WRITEFORMAT - invalid or unsupported format."
  esac
}

calcEndDate()
{
  if [[ x$SSLCMD = x ]]; then
    #statements
    error "$SSLCMD command not found!"
  fi
  # when cert dir is given
  if [[ $DIR -eq 1 ]]; then
    #statements
    for CERTDIR in ${TARGETDIR[@]}
    do
      ISCERTSEXISTS=$(ls -A $CERTDIR| egrep "*.$EXT$")
      if [[ -z ${ISCERTSEXISTS} ]]; then
        #statements
        warn "no certificate files at $CERTDIR with extention $EXT"
      fi
      for FILE in $(find $CERTDIR/ -maxdepth 2 -type f -iname "*.${EXT}")
      do
        log debug "Scanning certificate ${FILE}"

        SSLINFO=($(openssl x509 -in $FILE -noout -subject -issuer -serial | \
          sed -r 's/\s=\s/=/g;s/(.*),\s(.*)/\2/g;s/\s/|/g' | \
          awk -F= '{print $NF}'))
        
        log debug "processed certificate information - ${SSLINFO[*]}"

        EXPDATE=$($SSLCMD x509 -in $FILE -noout -enddate)
        
        log debug "Certificate ${FILE} expires on ${EXPDATE}"
        
        EXPEPOCH=$(date -d "${EXPDATE##*=}" +%s)
        CERTIFICATENAME=${FILE##*/}
        getExpiry $EXPEPOCH ${CERTIFICATENAME%%.*} "${SSLINFO[*]}"
      done
    done
  elif [[ $CONFIG -eq 1 ]]; then
    #statements
    while read LINE
    do
      log debug "Scanning certificate for ${LINE}"
      if echo "$LINE" | \
      egrep -q '^[a-zA-Z0-9.]+:[0-9]+|^[a-zA-Z0-9]+_.*:[0-9]+';
      then
        SSLINFO=($(echo | openssl s_client -connect $LINE 2>/dev/null | \
          openssl x509 -noout -subject -issuer -serial 2>/dev/null | \
          sed -r 's/\s=\s/=/g;s/(.*),\s(.*)/\2/g;s/\s/|/g' | \
          awk -F= '{print $NF}'))

        log debug "processed certificate information - ${SSLINFO[*]}"

        EXPDATE=$(echo | \
        openssl s_client -connect $LINE 2>/dev/null | \
        openssl x509 -noout -enddate 2>/dev/null);
        if [[ $EXPDATE = '' ]]; then
          #statements
          warn "[error:0906D06C] Cannot fetch certificates for $LINE"
        else
          log debug "Certificate ${LINE} expires on ${EXPDATE}"
        
          EXPEPOCH=$(date -d "${EXPDATE##*=}" +%s);
          CERTIFICATENAME=${LINE%%:*};
          getExpiry $EXPEPOCH ${CERTIFICATENAME} "${SSLINFO[*]}"
        fi
      else
        warn "[format error] $LINE is not in required format!"
      fi
    done < $CONFIGFILE
  fi
}

getExpiry()
{
  local EXPDATE=$1
  local CERTNAME=$2
  local DATA=($3)
  TODAY=$(date +%s)
  TIMETOEXPIRE=$(( ($EXPDATE - $TODAY)/(60*60*24) ))
  log debug "${CERTNAME}.${EXT} will expire in ${TIMETOEXPIRE} days"
  ((SCANNED+=1))
  
  if [[ ${TIMETOEXPIRE} -le 0 ]]; then
    ((EXPIRED+=1))
  fi

  log debug "extracted ssl information - ${DATA[*]}"

  EXPCERTS=( ${EXPCERTS[@]} "${CERTNAME};${DATA[0]};${DATA[1]};${DATA[2]};$TIMETOEXPIRE" )
  log debug "Expiring certificates - ${EXPCERTS[*]}"
}

# your script goes here
while getopts ":c:d:w:o:e:l:h" OPTIONS
do
case $OPTIONS in
  c ) CONFIG=1
      CONFIGFILE="$OPTARG"
      if [[ ! -e $CONFIGFILE ]] || [[ ! -s $CONFIGFILE ]]; then
        #statements
        error "$CONFIGFILE does not exist or empty!"
      fi;;

  e ) EXT="$OPTARG"
      case $EXT in
        crt|pem|cert )
        log info "Extention check complete."
        ;;
        * )
        error "invalid certificate extention $EXT!"
        ;;
      esac;;

  d ) DIR=1
      TARGETDIR="${OPTARG//,/ }"
      [[ ${#TARGETDIR[@]} -eq 0 ]] && error "$TARGETDIR empty variable!";;

  w ) WRITEFORMAT="$OPTARG";;

  o ) OUTFILE="$OPTARG";;

  l ) LOGLEVEL="$OPTARG";;

  h ) usage;;

  \? ) usage;;

  : ) error "Argument required !!! see '-h' for help";;
esac
done
shift $(($OPTIND - 1))
#
calcEndDate
#finally print the list
if [[ ${OUTFILE} = "" ]]; then
  printOutput ${EXPCERTS[@]}
else
  printOutput ${EXPCERTS[@]} > ${OUTFILE}
  # handle permissions for the files paret directory
  chmod -R 755 ${OUTFILE%/*}
fi