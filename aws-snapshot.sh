#!/bin/bash
# Project Source: https://github.com/renanvicente/vol-ami-snapshot-aws
# Version:        0.0.1
# Author:         Renan Vicente
# Mail:           renanvice@gmail.com
# Website:        http://www.renanvicente.com
# Github:         https://www.github.com/renanvicente
# Linkedin:       http://www.linkedin.com/pub/renan-silva/6a/802/59b/en



DIR=$(dirname "${BASH_SOURCE[0]}")
# Dates
DATECHECK_7d=`date +%Y-%m-%d --date "$RETENTION days ago"`
DATENOW=`date +'%Y-%m-%d   %H-%M-%S'`


# Check if have a parameter -f to load config file
while getopts f: OPT
do
        case $OPT in
                f) CONFIG_FILE="$OPTARG"
        esac
done

if [ ! -z "$CONFIG_FILE" ] ; then
  if [ -f $CONFIG_FILE ];then
	. $CONFIG_FILE
  fi
elif [ -f "$DIR/aws-snapshot.conf" ]; then
  . $DIR/aws-snapshot.conf
else
  logger -s "unable to read the configuration file, plese create aws-snapshot.conf"
  exit 1
fi

# Wrapper for Debug mode
runcmd() {

    if [ $DEBUG -eq 1 ]; then
        echo DEBUG: --- "$@"
        "$@" 2>&1 | tee -a $LOG_FILE
    else
	"$@" &>> $LOG_FILE
    fi  
}


function attach_params {

  PARAMS="-O $AWS_ACCESS_KEY -W $AWS_SECRET_KEY --region $EC2_REGION_NAME"

}

function delete_old_snapshots () {

  DATECHECK_ND=`date +%Y-%m-%d --date "$RETENTION days ago"`
  OLD_IMAGES=$($EC2_BIN/ec2-describe-images $PARAMS  |  grep -E 'IMAGE|Generated_by_script_aws_snapshoot_renanvicente'  | awk '{print $2,$4}' |  awk '($2 <= "\$DATECHECK_ND"){print $1}' | grep -v "`cat $EXCLUDES_IMAGES`")
  for IMAGE in $OLD_IMAGES ; do
    runcmd $EC2_BIN/ec2-deregister $PARAMS $IMAGE
  done
  OLD_VOLUMES=$($EC2_BIN/ec2-describe-snapshots $PARAMS  | awk '{print $5,$2}'  |  awk -F'T' '{print $1,$2}' | awk '($1 <= "\$DATECHECK_ND"){print $3}' | grep -v "`cat $EXCLUDES_VOLUMES`")
  echo $OLD_VOLUMES
  for SNAPSHOT_ID in $OLD_VOLUMES ; do
    runcmd echo "Deleting snapshot $SNAPSHOT_ID"
    runcmd $EC2_BIN/ec2-delete-snapshot $PARAMS $SNAPSHOT_ID
  done
}

function backup() {
  
    INSTANCES=`$EC2_BIN/ec2-describe-instances $PARAMS --filter "tag-key=$TAG_NAME,tag-value=$TAG_VALUE" | grep INSTANCE | awk '{print $2}'`
    runcmd echo "`echo $INSTANCES | tr ' ' '\n' | wc -l` Instances to back up ( `echo $INSTANCES | tr ' ' ',' ` )"
    for INSTANCE in $INSTANCES; do
      if [ $SNAPSHOT_BASED_ON_IMAGE -eq 1 ]; then
        runcmd $EC2_BIN/ec2-create-image $PARAMS --no-reboot --name \'"INSTANCEID.${INSTANCE}_DATE.   ${DATENOW}_Generated_by_script_aws_snapshoot_renanvicente"\' $INSTANCE
      elif [ $SNAPSHOT_BASED_ON_VOLUME -eq 1 ]; then
        VOLUMES=`$EC2_BIN/ec2-describe-volumes $PARAMS --filter "attachment.instance-id=$INSTANCE" | grep VOLUME | awk '{print $2}'`
        runcmd echo "`echo $VOLUMES | tr ' ' '\n' | wc -l` Volumes to back up on $INSTANCE ( `echo $VOLUMES | tr ' ' ',' ` )"
        for VOLUME in $VOLUMES; do
          runcmd $EC2_BIN/ec2-create-snapshot $PARAMS -d "INSTANCE-ID:${INSTANCE}_VOL-ID:${VOLUME}-DATE:${DATENOW}" $VOLUME
        done
      else
        runcmd echo "ERROR: SNAPSHOT BASED ON NOTHING, please make sure that you choose your way to back up"
       fi
    done
  
}



# Add entry in logfile for run begin
runcmd echo "${DATENOW} ======= BEGIN SNAPSHOT SCRIPT ========="
attach_params
delete_old_snapshots
backup

runcmd echo "$(date +'%Y-%m-%d   %H-%M-%S') ======= END SNAPSHOT SCRIPT ========="
