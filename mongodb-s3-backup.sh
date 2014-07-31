#!/bin/bash
#
# Argument = -u user -p password -k key -s secret -b bucket
#
# To Do - Abstract bucket region to options

# Exit immediately if a command exits with a non-zero status.
set -e

usage()
{
cat << EOF
usage: $0 options

This script dumps the current mongo database, tars and gzips it, then sends it to an Amazon S3 bucket.

OPTIONS:
   -h      Show this message
   -u      Mongodb user
   -p      Mongodb password
   -m      Mongodb Host and Port
   -d      Mongodb database name
   -k      AWS Access Key
   -s      AWS Secret Key
   -r      Amazon S3 region
   -b      Amazon S3 bucket name
   -n      backup name prefix (optional)
EOF
}

MONGODB_USER=
MONGODB_PASSWORD=
MONGODB_HOST=
MONGODB_DB=
AWS_ACCESS_KEY=
AWS_SECRET_KEY=
S3_REGION=
S3_BUCKET=
BACKUP_PREFIX=

while getopts “ht:u:p:k:s:r:b:” OPTION
do
  case $OPTION in
    h)
      usage
      exit 1
      ;;
    u)
      MONGODB_USER=$OPTARG
      ;;
    p)
      MONGODB_PASSWORD=$OPTARG
      ;;
    m)
      MONGODB_HOST=$OPTARG
      ;;
    d)
      MONGODB_DB=$OPTARG
      ;;
    k)
      AWS_ACCESS_KEY=$OPTARG
      ;;
    s)
      AWS_SECRET_KEY=$OPTARG
      ;;
    r)
      S3_REGION=$OPTARG
      ;;
    b)
      S3_BUCKET=$OPTARG
      ;;
    n)
      BACKUP_PREFIX=$OPTARG
      ;;
    ?)
      usage
      exit
    ;;
  esac
done

if [[ -z $MONGODB_USER ]] || [[ -z $MONGODB_PASSWORD ]] || [[ -z $AWS_ACCESS_KEY ]] || [[ -z $AWS_SECRET_KEY ]] || [[ -z $S3_REGION ]] || [[ -z $S3_BUCKET ]] || [[ -z $MONGODB_HOST ]] || [[ -z $MONGODB_DB]]
then
  usage
  exit 1
fi

# Get the directory the script is being run from
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
echo $DIR
# Store the current date in YYYY-mm-DD-HHMMSS
DATE=$(date -u "+%F-%H%M%S")
FILE_NAME="$BACKUP_PREFIX-backup-$DATE"
ARCHIVE_NAME="$FILE_NAME.tar.gz"

# Dump the database
echo "Dumping Database: $MONGODB_DB"
mongodump -v --oplog --host $MONGODB_HOST --db $MONGODB_DB -u $MONGODB_USER -p $MONGODB_PASSWORD --out $DIR/backup/$FILE_NAME

# Tar Gzip the file
echo "Compressing Backup into $ARCHIVE_NAME"
tar -C $DIR/backup/ -zcvf $DIR/backup/$ARCHIVE_NAME $FILE_NAME/

#todo: Encrypt Archive?

# Remove the backup directory
echo 'Removing old backup directory'
rm -r $DIR/backup/$FILE_NAME

# Send the file to the backup drive or S3
HEADER_DATE=$(date -u "+%a, %d %b %Y %T %z")
CONTENT_MD5=$(openssl dgst -md5 -binary $DIR/backup/$ARCHIVE_NAME | openssl enc -base64)
CONTENT_TYPE="application/x-download"
STRING_TO_SIGN="PUT\n$CONTENT_MD5\n$CONTENT_TYPE\n$HEADER_DATE\n/$S3_BUCKET/$ARCHIVE_NAME"
SIGNATURE=$(echo -e -n $STRING_TO_SIGN | openssl dgst -sha1 -binary -hmac $AWS_SECRET_KEY | openssl enc -base64)

echo 'Uploading backup to S3'
curl -X PUT \
--header "Host: $S3_BUCKET.s3-$S3_REGION.amazonaws.com" \
--header "Date: $HEADER_DATE" \
--header "content-type: $CONTENT_TYPE" \
--header "Content-MD5: $CONTENT_MD5" \
--header "Authorization: AWS $AWS_ACCESS_KEY:$SIGNATURE" \
--upload-file $DIR/backup/$ARCHIVE_NAME \
https://$S3_BUCKET.s3-$S3_REGION.amazonaws.com/$ARCHIVE_NAME

echo 'done'
