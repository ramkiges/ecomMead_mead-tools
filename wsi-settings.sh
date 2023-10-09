#!/bin/bash
# mimics wsi_settings but invokes the jenkins job instead of directly manipulating the filesystem
PATH=/opt/homebrew/bin:/apps/mead-tools:/usr/local/bin:/usr/local/sbin:/apps/java/bin:/bin:/bin:/usr/bin:/usr/sbin:/sbin:~/bin
export PATH
[[ -z $DELIM ]] && DELIM='='
#export VERBOSE=
export DEBUG=

BailOut() {
  [[ -n $1 ]] && echo "$(hostname)/$(basename $0): $*" >&2

	exit 1
}

WSI_SETTINGS=$(which wsi_settings 2>/dev/null)
[ -z "$WSI_SETTINGS" ] && BailOut "Can't find wsi_settings"

JENKINS=$(which jenkins-jnlp 2>/dev/null)
[ -z "$JENKINS" ] && BailOut "Can't find jenkins-jnlp"

# parse arguments
while [[ $# -gt 0 ]]
do
  case $1 in
        -v|--verbose )
                VERBOSE=true
                shift;;

        -d|--debug )
                $(echo "$2" | grep -q -- "^-") || { DEBUG="-d"; }
                shift;;

        -r|--repo|--devops )
                $(echo "$2" | grep -q -- "^-") || { DEVOPS_REPO="$2"; }
                shift;;

              --comment | -c )  
              $(echo "$2" | grep -q -- "^-") || { COMMENTS="$2"; }
              shift
            ;;

              --ticket | --jira | -t )  
              $(echo "$2" | grep -q -- "^-") || { TICKET="$2"; }
              shift
            ;;

                --env | -e )  
                        $(echo "$2" | grep -q -- "^-") || { ENVIRO="$2"; }
                        shift
		        ;;

                --brand | -b )  
                        $(echo "$2" | grep -q -- "^-") || { BRAND="$2"; }
                        shift
		        ;;

                --type )  
                        $(echo "$2" | grep -q -- "^-") || { TYPE="$2"; }
                        shift
			            VALUE="$2"
      			    shift
		        ;;

                update )  
                        ACTION="$1"
			            shift
            			SETTING="$1"
		            	shift
           		;;

                --override | --bulk )
                        ACTION="update"
                        shift   
                        BULK="$*"
                        break
                ;;

                * ) shift ;;
	esac
done

#[[ -n $VERBOSE && -n $DEVOPS_REPO ]] && echo "DEVOPS_REPO=" >&2
# logic to process bulk appsettings
if [[ -n $BULK ]]
then
    LEFT=$(echo "$BULK" | cut -d= -f 1)
    VALUE=$(echo "$BULK" | cut -d$DELIM -f 2- | awk '{$1=$1};1')

    LEFT=$(echo "$LEFT" | sed -es!/!.!g)
    LEFT=$(echo "$LEFT" | sed -es/"\.'.*'"//g)
    LEFT=$(echo "$LEFT" | sed -es/[[:space:]]//g)

    SETTING=$(echo "$LEFT" | awk -F\. '{ print $1 "." $2 }')
    TYPE=$(echo "$LEFT" | awk -F '[./]' '{ print $3 }' | awk -F '[=:]' '{ print $1 }')

    GROUP=$(echo "$LEFT" | awk -F\. '{ print $1 }')
    NAME=$(echo "$LEFT" | awk -F\. '{ print $2 }')
    [[ -z $TYPE ]] && BailOut "Setting GROUP.NAME.TYPE mal-formed: GROUP=$GROUP NAME=$NAME TYPE=$TYPE"
fi

[[ -z $BRAND ]] && BailOut "Need brand"
[[ -z $ENVIRO ]] && BailOut "Need env"
[[ -z $TYPE ]] && BailOut "Need type for $SETTING"
[[ -z $SETTING ]] && BailOut "Need setting"

BRAND=$(echo "$BRAND" | tr '[:upper:]' '[:lower:]')
ENVIRO=$(echo "$ENVIRO" | tr '[:upper:]' '[:lower:]')
COMMENTS=$(sed -es/"-c "//g <<< $COMMENTS)

[[ -n $DEBUG ]] && echo "$(basename $0): $BRAND $ENVIRO $SETTING"
#set -x
if [[ -n $ADHOC || $BRAND =~ adm ]]
then
  #set -x
  jenkins-jnlp build adhoc-appsetting \
    -p Ticket="$TICKET" \
    -p Brands="$(tr '[:lower:]' '[:upper:]' <<< $BRAND)" \
    -p Environments="$ENVIRO" \
    -p DataType=$TYPE \
    -p Setting="$SETTING" \
    -p Value="$VALUE" \
    -p Action=$ACTION \
    -p RunBy=$(basename $0) \
    -p Comments="\"$COMMENTS\""
  { set +x; } 2>/dev/null
else
  #set -x
  [[ -n $VERBOSE ]] && echo "+ $(basename $0): $ACTION $BRAND $ENVIRO $SETTING" >&2
  wsi_settings --brand $BRAND --env $ENVIRO update $SETTING --type $TYPE "$VALUE" --comments "$COMMENTS" $DEBUG --force
  { set +x; } 2>/dev/null
fi
{ set +x; } 2>/dev/null

exit 0
