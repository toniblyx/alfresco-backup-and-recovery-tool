#! /usr/bin/env bash
#
# Copyright (c) 2013 Toni de la Fuente.
#
# This program is free software: you can redistribute it and/or modify it under
# the terms of the Apache License as published by the Apache Foundation.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. 
#
# Most recent information about this tool is available in:
# http://blyx.com/alfresco-bart
#
# Latest code available at:
# http://blyx.com/alfresco-bart
#
#########################################################################################
# alfresco-bart: ALFRESCO BACKUP AND RECOVERY TOOL 
# Version 0.3     
#########################################################################################
# ACTION REQUIRED:
# CONFIGURE alfresco-bart in the alfresco-bart.properties file and ALFBRT_PATH
# in this file.
# Copy all files into your ALFRESCO_INSTALLATION_PATH/scripts.
# RUN ./alfresco-bart.sh [backup|recovery|verify|collection|list] 
#########################################################################################
#
# Run backup daily at 5AM
# 0 5 * * * root /path/to/alfresco-bart.sh backup 
#
#########################################################################################

# Load properties
if [ -n "$ALFBRT_PATH" ]; then
  ALFBRT_PATH="$ALFBRT_PATH"
else
  ALFBRT_PATH="/opt/alfresco/scripts"
fi

if [ -f ${ALFBRT_PATH}/alfresco-bart.properties ]; then
	. ${ALFBRT_PATH}/alfresco-bart.properties 
else
	echo alfresco-bart.properties file not found, edit $0 and modify ALFBRT_PATH
fi

# Do not let this script run more than once
PROC=`ps axu | grep -v "grep" | grep --count "duplicity"`
if [ $PROC -gt 0 ]; then 
	echo "alfresco-bart.sh or duplicity is already running."
	exit 1
fi

# Command usage menu
usage(){
echo "USAGE:
    `basename $0` <mode> [set] [date <dest>]

Modes:
    backup [set]	runs an incremental backup or a full if first time
    restore [set] [date] [dest]	runs the restore, wizard if no arguments
    verify [set]	verifies the backup
    collection [set]	shows all the backup sets in the archive
    list [set]		lists the files currently backed up in the archive

Sets:
    all		do all backup sets
    index	use index backup set (group) for selected mode
    db		use data base backup set (group) for selected mode
    cs		use content store backup set (group) for selected mode
    files	use rest of files backup set (group) for selected mode"
}

# Checks if encryption is required if not it adds appropiate flag
if [ $ENCRYPTION_ENABLED = "true" ]; then
	export PASSPHRASE
else
	NOENCFLAG="--no-encryption"
fi

# Checks backup type, target selected
case $BACKUPTYPE in
	"s3" ) 
	        export AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID}"
                export AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY}"
		DEST=${S3FILESYSLOCATION}
		PARAMS="${GLOBAL_DUPLICITY_PARMS} ${GLOBAL_DUPLICITY_CACHE_PARMS} ${S3OPTIONS} ${NOENCFLAG}"
		;;
	"ftp" ) 
		if [ ${FTPS_ENABLE} == 'false' ]; then
   			DEST=ftp://${FTP_USER}:${FTP_PASSWORD}@${FTP_SERVER}:${FTP_PORT}/${FTP_FOLDER}
   			PARAMS="${GLOBAL_DUPLICITY_PARMS} ${GLOBAL_DUPLICITY_CACHE_PARMS} ${NOENCFLAG}"
		else
   			DEST=ftps://${FTP_USER}:${FTP_PASSWORD}@${FTP_SERVER}:${FTP_PORT}/${FTP_FOLDER}
   			PARAMS="${GLOBAL_DUPLICITY_PARMS} ${GLOBAL_DUPLICITY_CACHE_PARMS} ${NOENCFLAG}"
		fi
		;;	
	"scp" )
		if [ "$SCP_PORT" != "" ]; then
			DEST=scp://${SCP_USER}@${SCP_SERVER}:${SCP_PORT}/${SCP_FOLDER}
		else
			DEST=scp://${SCP_USER}@${SCP_SERVER}/${SCP_FOLDER}
		fi
		PARAMS="${GLOBAL_DUPLICITY_PARMS} ${GLOBAL_DUPLICITY_CACHE_PARMS} ${NOENCFLAG}"
		;;
	"sftp" )
		if [ "$SFTP_PORT" != "" ]; then
			DEST=sftp://${SFTP_USER}@${SFTP_SERVER}:$SFTP_PORT}/${SFTP_FOLDER}
		else
			DEST=sftp://${SFTP_USER}@${SFTP_SERVER}/${SFTP_FOLDER}
		fi
		PARAMS="${GLOBAL_DUPLICITY_PARMS} ${GLOBAL_DUPLICITY_CACHE_PARMS} ${NOENCFLAG}"
		;;
	"local" )
		# command sintax is "file:///" but last / is coming from ${LOCAL_BACKUP_FOLDER} variable
		DEST=file://${LOCAL_BACKUP_FOLDER}
		PARAMS="${GLOBAL_DUPLICITY_PARMS} ${GLOBAL_DUPLICITY_CACHE_PARMS} ${NOENCFLAG}"
		;;
	* ) echo "`date +%F-%X` - [ERROR] Unknown BACKUP type <$BACKUPTYPE>, review your alfresco-backup.properties" >> $ALFBRT_LOG_FILE;; 
esac
	
# Checks if logs directory exist 
if [ ! -d $ALFBRT_LOG_DIR ]; then
	echo Script logs directory not found, add a valid directory in 'ALFBRT_LOG_DIR'. Bye.
	exit 1
fi

function indexBackup {
	echo >> $ALFBRT_LOG_FILE
	echo "`date +%F-%X` - $BART_LOG_TAG Backing up the Alfresco indexes to $BACKUPTYPE" >> $ALFBRT_LOG_FILE
  	echo "`date +%F-%X` - $BART_LOG_TAG Starting backup - Alfresco $INDEXTYPE indexes" >> $ALFBRT_LOG_FILE
  	# Command for indexes backup
	echo "`date +%F-%X` - $BART_LOG_TAG Running command - $DUPLICITYBIN $PARAMS $INDEXES_BACKUP_DIR $DEST/$INDEXTYPE" >> $ALFBRT_LOG_FILE
  	$DUPLICITYBIN $PARAMS $INDEXES_BACKUP_DIR $DEST/index/backup >> $ALFBRT_LOG_FILE
  	if [ ${INDEXTYPE} == 'solr' ]; then
		echo "`date +%F-%X` - $BART_LOG_TAG Running command - $DUPLICITYBIN $PARAMS $INDEXES_DIR --exclude $INDEXES_DIR/archive --exclude $INDEXES_DIR/workspace $DEST/index/config" >> $ALFBRT_LOG_FILE
  		$DUPLICITYBIN $PARAMS $INDEXES_DIR --exclude $INDEXES_DIR/archive --exclude $INDEXES_DIR/workspace $DEST/index/config >> $ALFBRT_LOG_FILE
	fi
	echo "`date +%F-%X` - $BART_LOG_TAG Indexes backup finished" >> $ALFBRT_LOG_FILE
}

function dbBackup {
	echo >> $ALFBRT_LOG_FILE
	echo "`date +%F-%X` - $BART_LOG_TAG Backing up the Alfresco db to $BACKUPTYPE" >> $ALFBRT_LOG_FILE
	echo "`date +%F-%X` - $BART_LOG_TAG Starting backup - Alfresco $DBTYPE db" >> $ALFBRT_LOG_FILE
	
	if [ ! -d $ALFBRT_LOG_DIR ]; then
		echo Script logs directory not found, add a valid directory in 'ALFBRT_LOG_DIR'. Bye.
		exit 1
	fi
	
	if [ ! -d $LOCAL_BACKUP_DB_DIR ]; then
		mkdir $LOCAL_BACKUP_DB_DIR
	fi
	
	case $DBTYPE in 
		"mysql" ) 
			echo "`date +%F-%X` - $BART_LOG_TAG Backing up the Alfresco DB to $BACKUPTYPE" >> $ALFBRT_LOG_FILE
  			echo "`date +%F-%X` - $BART_LOG_TAG Starting backup - Alfresco $DBTYPE DB" >> $ALFBRT_LOG_FILE
			# Mysql dump
			echo "`date +%F-%X` - $BART_LOG_TAG Running command - $MYSQL_BINDIR/$MYSQLDUMP_BIN --single-transaction  -u $DBUSER -h $DBHOST -p$DBPASS $DBNAME | $GZIP -9 > $LOCAL_BACKUP_DB_DIR/$DBNAME.dump" >> $ALFBRT_LOG_FILE
			$MYSQL_BINDIR/$MYSQLDUMP_BIN --single-transaction -u $DBUSER -h $DBHOST -p$DBPASS $DBNAME | $GZIP -9 > $LOCAL_BACKUP_DB_DIR/$DBNAME.dump
			echo "`date +%F-%X` - $BART_LOG_TAG Running command - $DUPLICITYBIN $PARAMS $LOCAL_BACKUP_DB_DIR $DEST/db" >> $ALFBRT_LOG_FILE
  			$DUPLICITYBIN $PARAMS $LOCAL_BACKUP_DB_DIR $DEST/db >> $ALFBRT_LOG_FILE
  			echo "`date +%F-%X` - $BART_LOG_TAG cleaning DB backup" >> $ALFBRT_LOG_FILE
  			rm -fr $LOCAL_BACKUP_DB_DIR/$DBNAME.dump
			echo "`date +%F-%X` - $BART_LOG_TAG DB backup finished" >> $ALFBRT_LOG_FILE
			
		;; 
		"postgresql" ) 		
			echo "`date +%F-%X` - $BART_LOG_TAG Backing up the Alfresco DB to $BACKUPTYPE" >> $ALFBRT_LOG_FILE
  			echo "`date +%F-%X` - $BART_LOG_TAG Starting backup - Alfresco $DBTYPE DB" >> $ALFBRT_LOG_FILE
			# PG dump in plain text format and compressed 
			echo "`date +%F-%X` - $BART_LOG_TAG Running command - $PGSQL_BINDIR/$PGSQLDUMP_BIN -Fc -w -h $DBHOST -U $DBUSER $DBNAME > $LOCAL_BACKUP_DB_DIR/$DBNAME.sql.Fc" >> $ALFBRT_LOG_FILE
			export PGPASSFILE=$PGPASSFILE
			export PGPASSWORD=$DBPASS
			$PGSQL_BINDIR/$PGSQLDUMP_BIN -Fc -w -h $DBHOST -U $DBUSER $DBNAME > $LOCAL_BACKUP_DB_DIR/$DBNAME.sql.Fc
			echo "`date +%F-%X` - $BART_LOG_TAG Running command - $DUPLICITYBIN $PARAMS $LOCAL_BACKUP_DB_DIR $DEST/db" >> $ALFBRT_LOG_FILE
  			$DUPLICITYBIN $PARAMS $LOCAL_BACKUP_DB_DIR $DEST/db >> $ALFBRT_LOG_FILE
		;; 
		
		"oracle" ) 
			echo "`date +%F-%X` - $BART_LOG_TAG Backing up the Alfresco DB to $BACKUPTYPE" >> $ALFBRT_LOG_FILE
  			echo "`date +%F-%X` - $BART_LOG_TAG Starting backup - Alfresco $DBTYPE DB" >> $ALFBRT_LOG_FILE
			# Oracle export 
			# TODO: Change full options
			echo "`date +%F-%X` - $BART_LOG_TAG Running command - $ORACLE_BINDIR/$ORASQLDUMP_BIN $DBUSER/$DBPASS@$DBHOST/$DBNAME full=y file=$LOCAL_BACKUP_DB_DIR/$DBNAME.dump log=$ALFBRT_LOG_FILE" >> $ALFBRT_LOG_FILE
			$ORACLE_BINDIR/$ORASQLDUMP_BIN $DBUSER/$DBPASS@$DBHOST/$DBNAME full=y file=$LOCAL_BACKUP_DB_DIR/$DBNAME.dump log=$ALFBRT_LOG_FILE
			echo "`date +%F-%X` - $BART_LOG_TAG Running command - $DUPLICITYBIN $PARAMS $LOCAL_BACKUP_DB_DIR $DEST/db" >> $ALFBRT_LOG_FILE
  			$DUPLICITYBIN $PARAMS $LOCAL_BACKUP_DB_DIR $DEST/db >> $ALFBRT_LOG_FILE
  			echo "`date +%F-%X` - $BART_LOG_TAG cleaning DB backup" >> $ALFBRT_LOG_FILE
  			rm -fr $LOCAL_BACKUP_DB_DIR/$DBNAME.dump
			echo "`date +%F-%X` - $BART_LOG_TAG DB backup finished" >> $ALFBRT_LOG_FILE
		;;
		
		* ) 
		echo "`date +%F-%X` - [ERROR] Unknown DB type \"$DBTYPE\", review your alfresco-bart.properties. Backup ABORTED!" >> $ALFBRT_LOG_FILE
		echo "`date +%F-%X` - [ERROR] Unknown DB type \"$DBTYPE\", review your alfresco-bart.properties. Backup ABORTED!"	
		exit 1
		;; 
	esac 
}

function contentStoreBackup {
	echo >> $ALFBRT_LOG_FILE
	# Getting a variable to know all includes and excludes
	CONTENTSTORE_DIR_INCLUDES="--include $ALF_CONTENTSTORE"
	if [ "$ALF_CONTENSTORE_DELETED" != "" ]; then
		CS_DIR_INCLUDE_DELETED=" --include $ALF_CONTENSTORE_DELETED"
	fi
	if [ "$ALF_CACHED_CONTENTSTORE" != "" ]; then
		CS_DIR_INCLUDE_CACHED=" --include $ALF_CACHED_CONTENTSTORE"
	fi
	if [ "$ALF_CONTENTSTORE2" != "" ]; then
		CS_DIR_INCLUDE_CS2=" --include $ALF_CONTENTSTORE2"
	fi
	if [ "$ALF_CONTENTSTORE3" != "" ]; then
		CS_DIR_INCLUDE_CS3=" --include $ALF_CONTENTSTORE3"
	fi
	if [ "$ALF_CONTENTSTORE4" != "" ]; then
		CS_DIR_INCLUDE_CS4=" --include $ALF_CONTENTSTORE4"
	fi
	if [ "$ALF_CONTENTSTORE5" != "" ]; then
		CS_DIR_INCLUDE_CS5=" --include $ALF_CONTENTSTORE5"
	fi
	
	CONTENTSTORE_EXCLUDE_PARENT_DIR="$(dirname "$ALF_CONTENTSTORE")"
  	
  	echo "`date +%F-%X` - $BART_LOG_TAG Backing up the Alfresco ContentStore to $BACKUPTYPE" >> $ALFBRT_LOG_FILE
  	echo "`date +%F-%X` - $BART_LOG_TAG Starting backup - Alfresco ContentStore" >> $ALFBRT_LOG_FILE
  	echo "`date +%F-%X` - $BART_LOG_TAG Running command - $DUPLICITYBIN $PARAMS $CONTENTSTORE_DIR_INCLUDES $CS_DIR_INCLUDE_DELETED $CS_DIR_INCLUDE_CACHED $CS_DIR_INCLUDE_CS2 $CS_DIR_INCLUDE_CS3 $CS_DIR_INCLUDE_CS4 $CS_DIR_INCLUDE_CS5 --exclude $CONTENTSTORE_EXCLUDE_PARENT_DIR $CONTENTSTORE_EXCLUDE_PARENT_DIR $DEST/cs" >> $ALFBRT_LOG_FILE
 
 	# Content Store backup itself 
  	$DUPLICITYBIN $PARAMS $CONTENTSTORE_DIR_INCLUDES $CS_DIR_INCLUDE_DELETED $CS_DIR_INCLUDE_CACHED \
  	$CS_DIR_INCLUDE_CS2 $CS_DIR_INCLUDE_CS3 $CS_DIR_INCLUDE_CS4 $CS_DIR_INCLUDE_CS5 \
  	--exclude $CONTENTSTORE_EXCLUDE_PARENT_DIR $CONTENTSTORE_EXCLUDE_PARENT_DIR \
  	$DEST/cs >> $ALFBRT_LOG_FILE
  	echo "`date +%F-%X` - $BART_LOG_TAG ContentStore backup done!" >> $ALFBRT_LOG_FILE
}

function filesBackup {
	echo >> $ALFBRT_LOG_FILE
    	# Getting a variable to know all includes and excludes
	FILES_DIR_INCLUDES="$ALF_INSTALLATION_DIR"
	
	if [ -d "$INDEXES_BACKUP_DIR" ]; then
		OPT_INDEXES_BACKUP_DIR=" --exclude **$INDEXES_BACKUP_DIR**"
	fi
	if [ -d "$INDEXES_DIR" ]; then
		OPT_INDEXES_DIR=" --exclude **$INDEXES_DIR**"
	fi
	if [ -d "$ALF_CONTENTSTORE" ]; then
		OPT_ALF_CONTENTSTORE=" --exclude **$ALF_CONTENTSTORE**"
	fi
	if [ -d ${ALF_DIRROOT}/contentstore.deleted ]; then
		OPT_ALF_CONTENSTORE_DELETED=" --exclude **${ALF_DIRROOT}/contentstore.deleted**"
	fi
	if [ -d "$ALF_CACHED_CONTENTSTORE" ]; then
		OPT_CACHED_CONTENTSTORE=" --exclude **$ALF_CACHED_CONTENTSTORE**"
	fi
	if [ -d "$ALF_CONTENTSTORE2" ]; then
		OPT_ALF_CONTENTSTORE2=" --exclude **$ALF_CONTENTSTORE2**"
	fi
	if [ -d "$ALF_CONTENTSTORE3" ]; then
		OPT_ALF_CONTENTSTORE3=" --exclude **$ALF_CONTENTSTORE3**"
	fi
	if [ -d "$ALF_CONTENTSTORE4" ]; then
		OPT_ALF_CONTENTSTORE4=" --exclude **$ALF_CONTENTSTORE4**"
	fi
	if [ -d "$ALF_CONTENTSTORE5" ]; then
		OPT_ALF_CONTENTSTORE5=" --exclude **$ALF_CONTENTSTORE5**"
	fi
	if [ -d "$LOCAL_BACKUP_DB_DIR" ]; then
		OPT_LOCAL_BACKUP_DB_DIR=" --exclude **$LOCAL_BACKUP_DB_DIR**"
	fi
	
  	echo "`date +%F-%X` - $BART_LOG_TAG Backing up the Alfresco files to $BACKUPTYPE" >> $ALFBRT_LOG_FILE
  	echo "`date +%F-%X` - $BART_LOG_TAG Starting backup - Alfresco files" >> $ALFBRT_LOG_FILE
  	echo "`date +%F-%X` - $BART_LOG_TAG Running command - $DUPLICITYBIN $PARAMS $FILES_DIR_INCLUDES $OPT_INDEXES_BACKUP_DIR $OPT_INDEXES_DIR $OPT_ALF_CONTENTSTORE $OPT_ALF_CONTENSTORE_DELETED $OPT_CACHED_CONTENTSTORE $OPT_ALF_CONTENTSTORE2 $OPT_ALF_CONTENTSTORE3 $OPT_ALF_CONTENTSTORE4 $OPT_ALF_CONTENTSTORE5 $OPT_LOCAL_BACKUP_DB_DIR $OPT_LOCAL_DB_DIR $DEST/files" >> $ALFBRT_LOG_FILE
 
 	# files backup itself 
  	$DUPLICITYBIN $PARAMS $FILES_DIR_INCLUDES $OPT_INDEXES_BACKUP_DIR $OPT_INDEXES_DIR \
  	$OPT_ALF_CONTENTSTORE $OPT_ALF_CONTENSTORE_DELETED $OPT_CACHED_CONTENTSTORE \
  	$OPT_ALF_CONTENTSTORE2 $OPT_ALF_CONTENTSTORE3 $OPT_ALF_CONTENTSTORE4 $OPT_ALF_CONTENTSTORE5 \
  	$OPT_LOCAL_BACKUP_DB_DIR $OPT_LOCAL_DB_DIR $DEST/files >> $ALFBRT_LOG_FILE
  	echo "`date +%F-%X` - $BART_LOG_TAG Files backup done!" >> $ALFBRT_LOG_FILE
}

function restoreOptions (){
	if [ "$WIZARD" = "1" ]; then
		RESTORE_TIME=$RESTOREDATE
		RESTOREDIR=$RESTOREDIR
	else
		RESTORE_TIME=$3
			if [ -z $4 ]; then
				usage
				exit 0
			else
				RESTOREDIR=$4
			fi
	fi
}
	
function restoreIndexes (){
	restoreOptions $1 $2 $3 $4
	if [ ${BACKUP_INDEX_ENABLED} == 'true' ]; then
		echo " =========== Starting restore INDEXES from $DEST/index to $RESTOREDIR/$INDEXTYPE ==========="
		echo "`date +%F-%X` - $BART_LOG_TAG - Recovery $RESTORE_TIME_FLAG $DEST/index/backup $RESTOREDIR/$INDEXTYPE/backup" >> $ALFBRT_LOG_FILE
		$DUPLICITYBIN restore --restore-time $RESTORE_TIME ${NOENCFLAG} ${GLOBAL_DUPLICITY_CACHE_PARMS} $DEST/index/backup $RESTOREDIR/$INDEXTYPE/backup
		
		if [ ${INDEXTYPE} == 'solr' ]; then
			echo "`date +%F-%X` - $BART_LOG_TAG - Recovery $RESTORE_TIME_FLAG $DEST/index/config $RESTOREDIR/$INDEXTYPE/config" >> $ALFBRT_LOG_FILE
			$DUPLICITYBIN restore --restore-time $RESTORE_TIME ${NOENCFLAG} ${GLOBAL_DUPLICITY_CACHE_PARMS} $DEST/index/config $RESTOREDIR/$INDEXTYPE/config	
		fi
		echo ""
		echo "INDEXES from $DEST/index... DONE!"
		echo ""
	fi
}

function restoreDb (){
	restoreOptions $1 $2 $3 $4
	if [ ${BACKUP_DB_ENABLED} == 'true' ]; then
		echo " =========== Starting restore DB from $DEST/db to $RESTOREDIR/db==========="
		echo "`date +%F-%X` - $BART_LOG_TAG - Recovery $RESTORE_TIME_FLAG $DEST/db $RESTOREDIR/db" >> $ALFBRT_LOG_FILE
		$DUPLICITYBIN restore --restore-time $RESTORE_TIME ${NOENCFLAG} ${GLOBAL_DUPLICITY_CACHE_PARMS} $DEST/db $RESTOREDIR/db
		if [ ${DBTYPE} == 'mysql' ]; then
			mv $RESTOREDIR/db/$DBNAME.dump $RESTOREDIR/db/$DBNAME.dump.gz
			echo ""
			echo "DB from $DEST/db... DONE!"
			echo ""
			echo "To restore this MySQL database use next command (the existing db must be empty)"
			echo "gunzip < $RESTOREDIR/db/$DBNAME.dump.gz | $MYSQL_BINDIR/mysql -u $DBUSER -p$DBPASS $DBNAME"
		fi
		if [ ${DBTYPE} == 'postgresql' ]; then
			echo ""
			echo "DB from $DEST/db... DONE!"
			echo ""
			echo "To restore this PostgreSQL database use next command (the existing db must be empty)"
			echo "$PGSQL_BINDIR/$PGSQLRESTORE_BIN -h $DBHOST -U $DBUSER -d $DBNAME $DBNAME.sql.Fc"
		fi
	else
		echo "No backup DB configured to backup. Nothing to restore."
	fi
}
	
function restoreContentStore (){
	restoreOptions $1 $2 $3 $4
	if [ ${BACKUP_CONTENTSTORE_ENABLED} == 'true' ]; then
		echo " =========== Starting restore CONTENT STORE from $DEST/cs to $RESTOREDIR/cs ==========="
		echo "`date +%F-%X` - $BART_LOG_TAG - Recovery $RESTORE_TIME_FLAG $DEST/cs $RESTOREDIR/cs" >> $ALFBRT_LOG_FILE
		$DUPLICITYBIN restore --restore-time $RESTORE_TIME ${NOENCFLAG} ${GLOBAL_DUPLICITY_CACHE_PARMS} $DEST/cs $RESTOREDIR/cs
		echo ""
		echo "CONTENT STORE from $DEST/cs... DONE!"
		echo ""
	else
		echo "No backup CONTENTSTORE configured to backup. Nothing to restore."
	fi
}
	
function restoreFiles (){
	restoreOptions $1 $2 $3 $4
	if [ ${BACKUP_FILES_ENABLED} == 'true' ]; then
		echo " =========== Starting restore FILES from $DEST/files to $RESTOREDIR/files ==========="
		echo "`date +%F-%X` - $BART_LOG_TAG - Recovery $RESTORE_TIME_FLAG $DEST/files $RESTOREDIR/files" >> $ALFBRT_LOG_FILE
		$DUPLICITYBIN restore --restore-time $RESTORE_TIME ${NOENCFLAG} ${GLOBAL_DUPLICITY_CACHE_PARMS} $DEST/files $RESTOREDIR/files
		echo ""
		echo "FILES from $DEST/files... DONE!"
		echo ""
	else
		echo "No backup FILES configured to backup. Nothing to restore."
	fi
}

function restoreWizard(){
	WIZARD=1
    clear
    echo "################## Welcome to Alfresco BART Recovery wizard ###################"
    echo ""
    echo " This backup and recovery tool does not overrides nor modify your existing	"
    echo " data, then you must have a destination folder ready to do the entire 	"
    echo " or partial restore process.											        "
    echo ""
    echo "##############################################################################"
    echo ""
    echo " Choose a restore option:"
    echo "	1) Full restore"
    echo " 	2) Set restore"
    echo "	3) Restore a single file of your Alfresco repository"
    echo "	4) Restore alfresco-global.properties from a given date"
    echo "	5) Restore other configuration file or directory"
    echo ""
    echo -n " Enter an option [1|2|3|4|5] or CTRL+c to exit: " 
    builtin read ASK1
    case $ASK1 in
    	1 ) 
    		RESTORECHOOSED=full
    		echo ""
    		echo " This wizard will help you to restore your Indexes, Data Base, Content Store and rest of files to a given directory."
    		echo ""
    		echo -n " Type a destination path with enough space available: "
    		builtin read RESTOREDIR
    		while [ ! -w $RESTOREDIR ]; do
    			echo " ERROR! Directory $RESTOREDIR does not exist or it does not have write permissions"
    			echo -n " please enter a valid path: "
    			builtin read RESTOREDIR
    		done
    		echo ""
    		echo -n " Do you want to see what backups collections are available to restore? [yes|no]: "
			read SHOWCOLANSWER
			shopt -s nocasematch
			case "$SHOWCOLANSWER" in
  				y|yes) 
  					collectionCommands collection all
					;;
  				n|no) 
    				;;
  				* ) echo "Incorrect value provided. Please enter yes or no." 
  				;; 
			esac
    		echo ""
    		echo " Specify a backup DATE (YYYY-MM-DD) to restore at or a number of DAYS+D since your valid backup. I.e.: if today is August 1st 2013 and want to restore a backup from July 26th 2013 then type \"2013-07-26\" or \"5D\" without quotes."
    		echo -n " Please type a date or number of days (use 'now' for last backup): " 
    		builtin read RESTOREDATE 
    		echo ""
    		echo " You want to restore a $RESTORECHOOSED backup from $BACKUPTYPE with date $RESTOREDATE to $RESTOREDIR"
    		echo -n " Is that correct? [yes|no]: "
    		read CONFIRMRESTORE
    		#duplicity restore --restore-time 
			read -p " To start restoring your selected backup press ENTER or CTRL+C to exit"
			echo ""
			restoreIndexes
			restoreDb
			restoreContentStore
			restoreFiles
			echo ""
			echo " Restore finished! Now you have to copy and replace your existing content with the content left in $RESTOREDIR, if you need a guideline about how to recovery your Alfresco installation from a backup please read the Alfresco Backup and Desaster Recovery White Paper file."
			echo ""
			exit 1
		;; 		
    	
  		2 ) 
  			RESTORECHOOSED=partial
    		echo ""
    		echo " This wizard will help you to restore one of your backup components: Indexes, Data Base, Content Store or rest of files to a given directory."
    		echo ""
    		echo -n " Type a component to restore [index|db|cs|files]: "
    		builtin read BACKUPGROUP
    		echo -n " Type a destination path with enough space available: "
    		builtin read RESTOREDIR
    		while [ ! -w $RESTOREDIR ]; do
    			echo " ERROR! Directory $RESTOREDIR does not exist or it does not have write permissions"
    			echo -n " please enter a valid path: "
    			builtin read RESTOREDIR
    		done
    		echo ""
    		echo -n " Do you want to see what backups collections are available for $BACKUPGROUP to restore? [yes|no]: "
			read SHOWCOLANSWER
			shopt -s nocasematch
			case "$SHOWCOLANSWER" in
  				y|yes) 
  					collectionCommands collection $BACKUPGROUP
					;;
  				n|no) 
    				;;
  				* ) echo "Incorrect value provided. Please enter yes or no." 
  				;; 
			esac
    		echo ""
    		echo " Specify a backup DATE (YYYY-MM-DD) to restore at or a number of DAYS+D since your valid backup. I.e.: if today is August 1st 2013 and want to restore a backup from July 26th 2013 then type \"2013-07-26\" or \"5D\" without quotes."
    		echo -n " Please type a date or number of days (use 'now' for last backup): " 
    		builtin read RESTOREDATE 
    		echo ""
    		echo " You want to restore a $RESTORECHOOSED backup of $BACKUPGROUP from $BACKUPTYPE with date $RESTOREDATE to $RESTOREDIR"
    		echo -n " Is that correct? [yes|no]: "
    		read CONFIRMRESTORE
    		#duplicity restore --restore-time 
			read -p " To start restoring your selected backup press ENTER or CTRL+C to exit"
			echo ""
			case $BACKUPGROUP in
			"index" )
				restoreIndexes
			;;
			"db" )
				restoreDb
			;;
			"cs" )
				restoreContentStore
			;;
			"files" )
				restoreFiles
    		;;
			* )
				echo "ERROR: Invalid parameter, there is no backup group with this name!"
		
			esac
			echo ""
			echo " Restore finished! Now you have to copy and replace your existing content with the content left in $RESTOREDIR, if you need a guideline about how to recovery your Alfresco installation from a backup please read the Alfresco Backup and Desaster Recovery White Paper."
			echo ""
			exit 1
		;;
		3 )
			echo ""
			echo " This option will restore a single content file from your backup."
    		echo " Type a backup DATE (YYYY-MM-DD) to restore at or a number of DAYS+D since your valid backup. I.e.: if today is August 1st 2013 and want to restore a backup from July 26th 2013 then type \"2013-07-26\" or \"5D\" without quotes."
    		echo -n " Please type a date or number of days: " 
    		builtin read RESTOREDATE 
    		echo " Type file name or any information about the file name you are looking for. I.e.: report."
    		echo -n " Document name: "
    		builtin read CONTENTCLUE
#    		echo " You want to restore a file like $CONTENTCLUE from $RESTOREDATE"
#    		echo -n " Is that correct? [yes|no]: "
#    		read CONFIRMRESTORE
#			read -p " To start restoring your selected file press ENTER or CTRL+C to exit"
			echo ""
			
			if [ ${DBTYPE} == 'mysql' ]; then
				restoreMysqlAtPointInTime
				searchNodeUrlInMysql
				restoreSelectedNode
				else
				echo "ONLY MYSQL IS SUPPORTED FOR SINGLE FILE RECOVERY YET. WAIT FOR NEXT VERSION"
				#	searchNodeUrlPosgres
				#	searchNodeUrlOracle
			fi	
		;;
		4 )
		echo "valid for Tomcat only *YET*"
		echo ""
    		echo " This option will restore an alfresco-global.properties backup. "
    		echo ""
    		echo -n " Type a destination path: "
    		builtin read RESTOREDIR
    		while [ ! -w $RESTOREDIR ]; do
    			echo " ERROR! Directory $RESTOREDIR does not exist or it does not have write permissions"
    			echo -n " please enter a valid path: "
    			builtin read RESTOREDIR
    		done
    		echo ""
    		echo -n " Do you want to see what backups collections are available for files to restore? [yes|no]: "
			read SHOWCOLANSWER
			shopt -s nocasematch
			case "$SHOWCOLANSWER" in
  				y|yes) 
  					collectionCommands collection files
					;;
  				n|no) 
    				;;
  				* ) echo "Incorrect value provided. Please enter yes or no." 
  				;; 
			esac
			
    		echo ""
    		echo " Type a backup DATE (YYYY-MM-DD) to restore at or a number of DAYS+D since your valid backup. I.e.: if today is August 1st 2013 and want to restore a backup from July 26th 2013 then type \"2013-07-26\" or \"5D\" without quotes."
    		echo -n " Please type a date or number of days (use 'now' for last backup): " 
    		builtin read RESTOREDATE 
    		echo ""
    		echo " You want to restore a $RESTORECHOOSED backup of alfresco-global.properties from $BACKUPTYPE with date $RESTOREDATE to $RESTOREDIR"
    		echo -n " Is that correct? [yes|no]: "
    		read CONFIRMRESTORE
			read -p " To start restoring your selected backup press ENTER or CTRL+C to exit"
			echo ""
			$DUPLICITYBIN restore --restore-time $RESTOREDATE ${NOENCFLAG} ${GLOBAL_DUPLICITY_CACHE_PARMS} --file-to-restore tomcat/shared/classes/alfresco-global.properties $DEST/files $RESTOREDIR/alfresco-global.properties
		
		;;

		5 )
			echo ""
    		echo " This option will restore any other file or directory from your installation or customization (files). "
    		echo ""
    		
    		echo ""
    		echo -n " Type the file or directory name you want to restore: "
			builtin read FILE_TO_SEARCH_IN_FILES
			echo ""
			echo " Looking for this file in the backup..."
			echo ""
			./`basename $0` list files|grep $FILE_TO_SEARCH_IN_FILES
			echo ""
			echo -n " Type the file or directory full path: "	
			builtin read FILE_TO_RESTORE_PATH
    		echo ""
    		echo " Type a backup DATE (YYYY-MM-DD) to restore at or a number of DAYS+D since your valid backup. I.e.: if today is August 1st 2013 and want to restore a backup from July 26th 2013 then type \"2013-07-26\" or \"5D\" without quotes."
    		echo -n " Please type a date or number of days (use 'now' for last backup): " 
    		builtin read RESTOREDATE 
    		echo ""
    		echo -n " Type a destination path: "
    		builtin read RESTOREDIR
    		while [ ! -w $RESTOREDIR ]; do
    			echo " ERROR! Directory $RESTOREDIR does not exist or it does not have write permissions"
    			echo -n " please enter a valid path: "
    			builtin read RESTOREDIR
    		done
    		FILE_TO_RESTORE=`basename $FILE_TO_RESTORE_PATH` 
    		echo " You want to restore a $RESTORECHOOSED backup of $FILE_TO_RESTORE from $BACKUPTYPE with date $RESTOREDATE to $RESTOREDIR"
    		echo -n " Is that correct? [yes|no]: "
    		read CONFIRMRESTORE
			read -p " To start restoring your selected backup press ENTER or CTRL+C to exit"
			echo ""
			$DUPLICITYBIN restore --restore-time $RESTOREDATE ${NOENCFLAG} ${GLOBAL_DUPLICITY_CACHE_PARMS} --file-to-restore $FILE_TO_RESTORE_PATH $DEST/files $RESTOREDIR/$FILE_TO_RESTORE
		;;
  		q ) 
  			exit 0
  		;;
  		* ) 
  			restoreWizard
  		;;
		esac
}			
	
function restoreMysqlAtPointInTime (){
		echo "`date +%F-%X` - $BART_LOG_TAG - Command: $DUPLICITYBIN restore --restore-time $RESTOREDATE ${NOENCFLAG} ${GLOBAL_DUPLICITY_CACHE_PARMS} --file-to-restore $DBNAME.dump $DEST/db /tmp/$DBNAME.dump.gz" >> $ALFBRT_LOG_FILE
		$DUPLICITYBIN restore --restore-time $RESTOREDATE ${NOENCFLAG} ${GLOBAL_DUPLICITY_CACHE_PARMS} --file-to-restore $DBNAME.dump $DEST/db /tmp/$DBNAME.dump.gz
		$GZIP -d /tmp/$DBNAME.dump.gz
		## TODO: Clean DB if its already populated
		echo "`date +%F-%X` - $BART_LOG_TAG - Command: $REC_MYSQL_BIN -h $REC_MYHOST -u $REC_MYUSER -p$REC_MYPASS $REC_MYDBNAME < /tmp/$DBNAME.dump" >> $ALFBRT_LOG_FILE
		$REC_MYSQL_BIN -h $REC_MYHOST -u $REC_MYUSER -p$REC_MYPASS $REC_MYDBNAME < /tmp/$DBNAME.dump >> $ALFBRT_LOG_FILE
		echo "`date +%F-%X` - $BART_LOG_TAG - Recovery DB populated" >> $ALFBRT_LOG_FILE
}

# Function to search a node URL based on a string in the node name, it shows a result and the user has to type the chosen node_id
function searchNodeUrlInMysql (){
		$REC_MYSQL_BIN -h $REC_MYHOST -u $REC_MYUSER -p$REC_MYPASS -D $REC_MYDBNAME -e "select node_id,string_value from alf_node_properties where STRING_VALUE like '%$CONTENTCLUE%'"
		echo " Type the node_id of the file you want to restore to /tmp."
    	echo -n " Document node_id: "
    	builtin read NODE_ID
		
		NODE_URL=`$REC_MYSQL_BIN -h $REC_MYHOST -u $REC_MYUSER -p$REC_MYPASS -D $REC_MYDBNAME -e "select n.id, u.content_url from alf_node n, alf_node_properties p, alf_namespace ns, alf_qname q, alf_content_data d, alf_content_url u where n.id = p.node_id and q.local_name = 'content' and ns.uri = 'http://www.alfresco.org/model/content/1.0' and ns.id = q.ns_id and p.qname_id = q.id and p.long_value = d.id and d.content_url_id = u.id and n.id=$NODE_ID;"|grep store|awk -F 'store:/' '{ print "contentstore" $2 }'`
		NODE_NAME=`$REC_MYSQL_BIN -h $REC_MYHOST -u $REC_MYUSER -p$REC_MYPASS -D $REC_MYDBNAME -e "select node_id,string_value from alf_node_properties where STRING_VALUE like '%$CONTENTCLUE%';"|grep $NODE_ID|awk -F'$NODE_ID' '{ print $2 }'`
		NODE_FORMAT=`file $ALF_DIRROOT/$NODE_URL`
		NODE_FILE_NAME=`$REC_MYSQL_BIN -h $REC_MYHOST -u $REC_MYUSER -p$REC_MYPASS -D $REC_MYDBNAME -e "select string_value from alf_node_properties where node_id='$NODE_ID';"|grep -v \||grep -v string_value|head -1|sed -e 's/ /_/g'`
		
		echo "Trying to restore $NODE_URL as $NODE_NAME " 
		echo ""
		echo "Node file format: $NODE_FORMAT"
		echo ""
		rm -fr /tmp/$DBNAME.dump
		echo "`date +%F-%X` - $BART_LOG_TAG - Cleaning recovery DB..." >> $ALFBRT_LOG_FILE
		echo ""
		$REC_MYSQL_BIN -h $REC_MYHOST -u $REC_MYUSER -p$REC_MYPASS -D $REC_MYDBNAME -e "drop database $REC_MYDBNAME;"
		$REC_MYSQL_BIN -h $REC_MYHOST -u $REC_MYUSER -p$REC_MYPASS -e "create database $REC_MYDBNAME;"
}

function restoreSelectedNode (){
		echo "`date +%F-%X` - $BART_LOG_TAG - Command: $DUPLICITYBIN restore --restore-time $RESTOREDATE ${NOENCFLAG} ${GLOBAL_DUPLICITY_CACHE_PARMS} --file-to-restore $NODE_URL $DEST/db /tmp/$NODE_FILE_NAME" >> $ALFBRT_LOG_FILE
		$DUPLICITYBIN restore --restore-time $RESTOREDATE ${NOENCFLAG} ${GLOBAL_DUPLICITY_CACHE_PARMS} --file-to-restore $NODE_URL $DEST/cs /tmp/$NODE_FILE_NAME
		echo ""
		echo "Whooooohooooo!!"
		echo ""
		echo "Your restored file has been placed in /tmp/$NODE_FILE_NAME rename with its name and format before opening if necessary."
}	

function verifyCommands (){
#    	if [ -z $2 ]; then	
#			echo "Please specify a valid backup group name to verify [index|db|cs|files|all]" 
#		else
		case $2 in
			"index" )	
				echo "=========================== BACKUP VERIFICATION FOR INDEXES $INDEXTYPE ==========================="
   				$DUPLICITYBIN verify -v${DUPLICITY_LOG_VERBOSITY} ${NOENCFLAG} --log-file=${ALFBRT_LOG_FILE} ${GLOBAL_DUPLICITY_CACHE_PARMS} $DEST/index/backup $INDEXES_BACKUP_DIR |grep snapshot
   				if [ ${INDEXTYPE} == 'solr' ]; then
  					$DUPLICITYBIN verify -v${DUPLICITY_LOG_VERBOSITY} ${NOENCFLAG} --log-file=${ALFBRT_LOG_FILE} ${GLOBAL_DUPLICITY_CACHE_PARMS} $DEST/index/config $INDEXES_DIR |grep snapshot
				fi
				echo "DONE!"
			;;
			"db" )
				echo "=========================== BACKUP VERIFICATION FOR DB $DBTYPE ==========================="    
    			$DUPLICITYBIN verify -v${DUPLICITY_LOG_VERBOSITY} ${NOENCFLAG} --log-file=${ALFBRT_LOG_FILE} ${GLOBAL_DUPLICITY_CACHE_PARMS} $DEST/db $LOCAL_BACKUP_DB_DIR
				echo "DONE!"
			;;
			"cs" )
				echo "=========================== BACKUP VERIFICATION FOR CONTENTSTORE ==========================="
    			$DUPLICITYBIN verify -v${DUPLICITY_LOG_VERBOSITY} ${NOENCFLAG} --log-file=${ALFBRT_LOG_FILE} ${GLOBAL_DUPLICITY_CACHE_PARMS} $DEST/cs $ALF_DIRROOT |grep contentstore
				echo "DONE!"
			;;
			"files" )
				echo "=========================== BACKUP VERIFICATION FOR FILES ==========================="
    			$DUPLICITYBIN verify -v${DUPLICITY_LOG_VERBOSITY} ${NOENCFLAG} --log-file=${ALFBRT_LOG_FILE} ${GLOBAL_DUPLICITY_CACHE_PARMS} $DEST/files $ALF_INSTALLATION_DIR | grep -v "alf_data\/solr"|grep -v "alf_data\/alfresco-db-backup"|grep -v "alf_data\/contentstore"
    			echo "DONE!"
			;;
			* )
				echo "=========================== BACKUP VERIFICATION FOR INDEXES $INDEXTYPE backup files ==========================="
				$DUPLICITYBIN verify -v${DUPLICITY_LOG_VERBOSITY} ${NOENCFLAG} --log-file=${ALFBRT_LOG_FILE} ${GLOBAL_DUPLICITY_CACHE_PARMS} $DEST/index/backup $INDEXES_BACKUP_DIR |grep snapshot ; \
				if [ ${INDEXTYPE} == 'solr' ]; then
					echo "=========================== BACKUP VERIFICATION FOR INDEXES $INDEXTYPE config files ==========================="
  					$DUPLICITYBIN verify -v${DUPLICITY_LOG_VERBOSITY} ${NOENCFLAG} --log-file=${ALFBRT_LOG_FILE} ${GLOBAL_DUPLICITY_CACHE_PARMS} $DEST/index/config $INDEXES_DIR |grep snapshot
				fi
				echo "=========================== BACKUP VERIFICATION FOR DB $DBTYPE ==========================="; \
	   			$DUPLICITYBIN verify -v${DUPLICITY_LOG_VERBOSITY} ${NOENCFLAG} --log-file=${ALFBRT_LOG_FILE} ${GLOBAL_DUPLICITY_CACHE_PARMS} $DEST/db $LOCAL_BACKUP_DB_DIR; \
	   			echo "=========================== BACKUP VERIFICATION FOR CONTENTSTORE ==========================="; \
				$DUPLICITYBIN verify -v${DUPLICITY_LOG_VERBOSITY} ${NOENCFLAG} --log-file=${ALFBRT_LOG_FILE} ${GLOBAL_DUPLICITY_CACHE_PARMS} $DEST/cs $ALF_DIRROOT |grep contentstore; \
				echo "=========================== BACKUP VERIFICATION FOR FILES ==========================="; \
				$DUPLICITYBIN verify -v${DUPLICITY_LOG_VERBOSITY} ${NOENCFLAG} --log-file=${ALFBRT_LOG_FILE} ${GLOBAL_DUPLICITY_CACHE_PARMS} $DEST/files $ALF_INSTALLATION_DIR | grep -v "alf_data\/solr"|grep -v "alf_data\/alfresco-db-backup"|grep -v "alf_data\/contentstore"
			;;
		esac 
#		fi
}

function listCommands(){
#		if [ -z $2 ]; then	
#			echo "Please specify a valid backup group name to list [index|db|cs|files|all]" 
#		else
		case $2 in
			"index" )
				$DUPLICITYBIN list-current-files -v${DUPLICITY_LOG_VERBOSITY} ${NOENCFLAG} --log-file=${ALFBRT_LOG_FILE} ${GLOBAL_DUPLICITY_CACHE_PARMS} $DEST/index/backup
				if [ ${INDEXTYPE} == 'solr' ]; then
  					$DUPLICITYBIN list-current-files -v${DUPLICITY_LOG_VERBOSITY} ${NOENCFLAG} --log-file=${ALFBRT_LOG_FILE} ${GLOBAL_DUPLICITY_CACHE_PARMS} $DEST/index/config
				fi
			;;
			"db" )
				$DUPLICITYBIN list-current-files -v${DUPLICITY_LOG_VERBOSITY} ${NOENCFLAG} --log-file=${ALFBRT_LOG_FILE} ${GLOBAL_DUPLICITY_CACHE_PARMS} $DEST/db
			;;
			"cs" )
				$DUPLICITYBIN list-current-files -v${DUPLICITY_LOG_VERBOSITY} ${NOENCFLAG} --log-file=${ALFBRT_LOG_FILE} ${GLOBAL_DUPLICITY_CACHE_PARMS} $DEST/cs
			;;
			"files" )
				$DUPLICITYBIN list-current-files -v${DUPLICITY_LOG_VERBOSITY} ${NOENCFLAG} --log-file=${ALFBRT_LOG_FILE} ${GLOBAL_DUPLICITY_CACHE_PARMS} $DEST/files 
			;;
			* )
				$DUPLICITYBIN list-current-files -v${DUPLICITY_LOG_VERBOSITY} ${NOENCFLAG} --log-file=${ALFBRT_LOG_FILE} ${GLOBAL_DUPLICITY_CACHE_PARMS} $DEST/index/backup; \
				$DUPLICITYBIN list-current-files -v${DUPLICITY_LOG_VERBOSITY} ${NOENCFLAG} --log-file=${ALFBRT_LOG_FILE} ${GLOBAL_DUPLICITY_CACHE_PARMS} $DEST/index/config; \
				$DUPLICITYBIN list-current-files -v${DUPLICITY_LOG_VERBOSITY} ${NOENCFLAG} --log-file=${ALFBRT_LOG_FILE} ${GLOBAL_DUPLICITY_CACHE_PARMS} $DEST/db; \
				$DUPLICITYBIN list-current-files -v${DUPLICITY_LOG_VERBOSITY} ${NOENCFLAG} --log-file=${ALFBRT_LOG_FILE} ${GLOBAL_DUPLICITY_CACHE_PARMS} $DEST/cs; \
				$DUPLICITYBIN list-current-files -v${DUPLICITY_LOG_VERBOSITY} ${NOENCFLAG} --log-file=${ALFBRT_LOG_FILE} ${GLOBAL_DUPLICITY_CACHE_PARMS} $DEST/files
			;;
		esac 
#		fi
}

function collectionCommands () {
#		if [ -z $2 ]; then	
#			echo " Please specify a valid backup group name to access its collection [index|db|cs|files|all]" 
#		else
		case $2 in
			"index" )	
				echo "======================= BACKUP COLLECTION FOR INDEXES $INDEXTYPE backup files ======================"
    			$DUPLICITYBIN collection-status -v0 ${NOENCFLAG} --log-file=${ALFBRT_LOG_FILE} ${GLOBAL_DUPLICITY_CACHE_PARMS} $DEST/index/backup
    			if [ ${INDEXTYPE} == 'solr' ]; then
    				echo "======================= BACKUP COLLECTION FOR INDEXES $INDEXTYPE config files ======================"
  					$DUPLICITYBIN collection-status -v0 ${NOENCFLAG} --log-file=${ALFBRT_LOG_FILE} ${GLOBAL_DUPLICITY_CACHE_PARMS} $DEST/index/config
				fi
			;;
			"db" )
				echo "=========================== BACKUP COLLECTION FOR DB $DBTYPE =========================="
    			$DUPLICITYBIN collection-status -v0 ${NOENCFLAG} --log-file=${ALFBRT_LOG_FILE} ${GLOBAL_DUPLICITY_CACHE_PARMS} $DEST/db
			;;
			"cs" )
				echo "========================== BACKUP COLLECTION FOR CONTENTSTORE ========================="
    			$DUPLICITYBIN collection-status -v0 ${NOENCFLAG} --log-file=${ALFBRT_LOG_FILE} ${GLOBAL_DUPLICITY_CACHE_PARMS} $DEST/cs
			;;
			"files" )
				echo "============================== BACKUP COLLECTION FOR FILES ============================"
    			$DUPLICITYBIN collection-status -v0 ${NOENCFLAG} --log-file=${ALFBRT_LOG_FILE} ${GLOBAL_DUPLICITY_CACHE_PARMS} $DEST/files
			;;
			* )
				echo "======================= BACKUP COLLECTION FOR INDEXES $INDEXTYPE ======================"
				$DUPLICITYBIN collection-status -v0 ${NOENCFLAG} --log-file=${ALFBRT_LOG_FILE} ${GLOBAL_DUPLICITY_CACHE_PARMS} $DEST/index/backup;
				if [ ${INDEXTYPE} == 'solr' ]; then     
					echo "======================= BACKUP COLLECTION FOR INDEXES $INDEXTYPE config files ======================";   
					$DUPLICITYBIN collection-status -v0 ${NOENCFLAG} --log-file=${ALFBRT_LOG_FILE} ${GLOBAL_DUPLICITY_CACHE_PARMS} $DEST/index/config; 
				fi
				echo "=========================== BACKUP COLLECTION FOR DB $DBTYPE =========================="; \
				$DUPLICITYBIN collection-status -v0 ${NOENCFLAG} --log-file=${ALFBRT_LOG_FILE} ${GLOBAL_DUPLICITY_CACHE_PARMS} $DEST/db; \
				echo "========================== BACKUP COLLECTION FOR CONTENTSTORE ========================="; \
				$DUPLICITYBIN collection-status -v0 ${NOENCFLAG} --log-file=${ALFBRT_LOG_FILE} ${GLOBAL_DUPLICITY_CACHE_PARMS} $DEST/cs; \
				echo "============================== BACKUP COLLECTION FOR FILES ============================"; \
				$DUPLICITYBIN collection-status -v0 ${NOENCFLAG} --log-file=${ALFBRT_LOG_FILE} ${GLOBAL_DUPLICITY_CACHE_PARMS} $DEST/files
			;;
		esac 
#		fi
}
    
function maintenanceCommands () {
	echo >> $ALFBRT_LOG_FILE	
	# Function to apply backup policies
	echo "`date +%F-%X` - $BART_LOG_TAG Running maintenance commands" >> $ALFBRT_LOG_FILE
	
	# Run maintenance if required/enabled
	if [ ${BACKUP_INDEX_ENABLED} == 'true' ]; then
		## INDEX backup collection maintenance
		echo "`date +%F-%X` - $BART_LOG_TAG Running command - $DUPLICITYBIN remove-older-than $CLEAN_TIME -v${DUPLICITY_LOG_VERBOSITY} --log-file=${ALFBRT_LOG_FILE} ${GLOBAL_DUPLICITY_CACHE_PARMS} --force $DEST/index/backup" >> $ALFBRT_LOG_FILE
  		$DUPLICITYBIN remove-older-than $CLEAN_TIME -v${DUPLICITY_LOG_VERBOSITY} --log-file=${ALFBRT_LOG_FILE} ${GLOBAL_DUPLICITY_CACHE_PARMS} --force $DEST/index/backup >> $ALFBRT_LOG_FILE
  		echo "`date +%F-%X` - $BART_LOG_TAG Running command - $DUPLICITYBIN remove-all-but-n-full $MAXFULL -v${DUPLICITY_LOG_VERBOSITY} --log-file=${ALFBRT_LOG_FILE} ${GLOBAL_DUPLICITY_CACHE_PARMS} --force $DEST/index/backup" >> $ALFBRT_LOG_FILE 2>&1
  		$DUPLICITYBIN remove-all-inc-of-but-n-full $MAXFULL -v${DUPLICITY_LOG_VERBOSITY} --log-file=${ALFBRT_LOG_FILE} ${GLOBAL_DUPLICITY_CACHE_PARMS} --force $DEST/index/backup >> $ALFBRT_LOG_FILE
  		if [ ${INDEXTYPE} == 'solr' ]; then
  			$DUPLICITYBIN remove-older-than $CLEAN_TIME -v${DUPLICITY_LOG_VERBOSITY} --log-file=${ALFBRT_LOG_FILE} ${GLOBAL_DUPLICITY_CACHE_PARMS} --force $DEST/index/config >> $ALFBRT_LOG_FILE
  			$DUPLICITYBIN remove-all-inc-of-but-n-full $MAXFULL -v${DUPLICITY_LOG_VERBOSITY} --log-file=${ALFBRT_LOG_FILE} ${GLOBAL_DUPLICITY_CACHE_PARMS} --force $DEST/index/config >> $ALFBRT_LOG_FILE
		fi
	fi
	
	if [ ${BACKUP_DB_ENABLED} == 'true' ]; then
		echo "`date +%F-%X` - $BART_LOG_TAG Running command - $DUPLICITYBIN remove-older-than $CLEAN_TIME -v${DUPLICITY_LOG_VERBOSITY} --log-file=${ALFBRT_LOG_FILE} ${GLOBAL_DUPLICITY_CACHE_PARMS} --force $DEST/db" >> $ALFBRT_LOG_FILE
		$DUPLICITYBIN remove-older-than $CLEAN_TIME -v${DUPLICITY_LOG_VERBOSITY} --log-file=${ALFBRT_LOG_FILE} ${GLOBAL_DUPLICITY_CACHE_PARMS} --force $DEST/db >> $ALFBRT_LOG_FILE
		echo "`date +%F-%X` - $BART_LOG_TAG Running command - $DUPLICITYBIN remove-all-but-n-full $MAXFULL -v${DUPLICITY_LOG_VERBOSITY} --log-file=${ALFBRT_LOG_FILE} ${GLOBAL_DUPLICITY_CACHE_PARMS} --force $DEST/db" >> $ALFBRT_LOG_FILE 2>&1
		$DUPLICITYBIN remove-all-inc-of-but-n-full $MAXFULL -v${DUPLICITY_LOG_VERBOSITY} --log-file=${ALFBRT_LOG_FILE} ${GLOBAL_DUPLICITY_CACHE_PARMS} --force $DEST/db >> $ALFBRT_LOG_FILE
	fi

	if [ ${BACKUP_CONTENTSTORE_ENABLED} == 'true' ]; then
		echo "`date +%F-%X` - $BART_LOG_TAG Running command - $DUPLICITYBIN remove-older-than $CLEAN_TIME -v${DUPLICITY_LOG_VERBOSITY} --log-file=${ALFBRT_LOG_FILE} ${GLOBAL_DUPLICITY_CACHE_PARMS} --force $DEST/cs" >> $ALFBRT_LOG_FILE
  		$DUPLICITYBIN remove-older-than $CLEAN_TIME -v${DUPLICITY_LOG_VERBOSITY} --log-file=${ALFBRT_LOG_FILE} ${GLOBAL_DUPLICITY_CACHE_PARMS} --force $DEST/cs >> $ALFBRT_LOG_FILE 2>&1
  		echo "`date +%F-%X` - $BART_LOG_TAG Running command - $DUPLICITYBIN remove-all-but-n-full $MAXFULL -v${DUPLICITY_LOG_VERBOSITY} --log-file=${ALFBRT_LOG_FILE} ${GLOBAL_DUPLICITY_CACHE_PARMS} --force $DEST/cs" >> $ALFBRT_LOG_FILE 2>&1
  		$DUPLICITYBIN remove-all-inc-of-but-n-full $MAXFULL -v${DUPLICITY_LOG_VERBOSITY} --log-file=${ALFBRT_LOG_FILE} ${GLOBAL_DUPLICITY_CACHE_PARMS} --force $DEST/cs >> $ALFBRT_LOG_FILE 2>&1
	fi
	if [ ${BACKUP_FILES_ENABLED} == 'true' ]; then
		echo "`date +%F-%X` - $BART_LOG_TAG Running command - $DUPLICITYBIN remove-older-than $CLEAN_TIME -v${DUPLICITY_LOG_VERBOSITY} --log-file=${ALFBRT_LOG_FILE} ${GLOBAL_DUPLICITY_CACHE_PARMS} --force $DEST/files" >> $ALFBRT_LOG_FILE
  		$DUPLICITYBIN remove-older-than $CLEAN_TIME -v${DUPLICITY_LOG_VERBOSITY} --log-file=${ALFBRT_LOG_FILE} ${GLOBAL_DUPLICITY_CACHE_PARMS} --force $DEST/files >> $ALFBRT_LOG_FILE 2>&1
  		echo "`date +%F-%X` - $BART_LOG_TAG Running command - $DUPLICITYBIN remove-all-but-n-full $MAXFULL -v${DUPLICITY_LOG_VERBOSITY} --log-file=${ALFBRT_LOG_FILE} ${GLOBAL_DUPLICITY_CACHE_PARMS} --force $DEST/files" >> $ALFBRT_LOG_FILE 2>&1
  		$DUPLICITYBIN remove-all-inc-of-but-n-full $MAXFULL -v${DUPLICITY_LOG_VERBOSITY} --log-file=${ALFBRT_LOG_FILE} ${GLOBAL_DUPLICITY_CACHE_PARMS} --force $DEST/files >> $ALFBRT_LOG_FILE 2>&1
	fi 
	echo "`date +%F-%X` - $BART_LOG_TAG Maintenance commands DONE!" >> $ALFBRT_LOG_FILE
}

# Main options
case $1 in
	"backup" ) 
		case $2 in
			"index" )
			# Run backup of indexes if enabled
			if [ ${BACKUP_INDEX_ENABLED} == 'true' ]; then
				indexBackup
			fi
			;;
			"db" )
			# Run backup of db if enabled
			if [ ${BACKUP_DB_ENABLED} == 'true' ]; then
				dbBackup
			fi
			;;
			"cs" )
			# Run backup of contentStore if enabled
			if [ ${BACKUP_CONTENTSTORE_ENABLED} == 'true' ]; then
				contentStoreBackup
			fi
			;;
			"files" )
			# Run backup of files if enabled
			if [ ${BACKUP_FILES_ENABLED} == 'true' ]; then
				filesBackup
			fi
			;;
			* )
				case $3 in 
					"force" )
						PARAMS="$PARAMS --allow-source-mismatch"
					;;
				esac
			
			echo "`date +%F-%X` - $BART_LOG_TAG Starting backup" >> $ALFBRT_LOG_FILE
			echo "`date +%F-%X` - $BART_LOG_TAG Set script variables done" >> $ALFBRT_LOG_FILE
			# Run backup of indexes if enabled
			if [ ${BACKUP_INDEX_ENABLED} == 'true' ]; then
				indexBackup
			fi
			# Run backup of db if enabled
			if [ ${BACKUP_DB_ENABLED} == 'true' ]; then
				dbBackup
			fi
			# Run backup of contentStore if enabled
			if [ ${BACKUP_CONTENTSTORE_ENABLED} == 'true' ]; then
				contentStoreBackup
			fi
			# Run backup of files if enabled
			if [ ${BACKUP_FILES_ENABLED} == 'true' ]; then
				filesBackup
			fi 
			# Maintenance commands (cleanups and apply retention policies)
			if [ ${BACKUP_POLICIES_ENABLED} == 'true' ]; then
				maintenanceCommands
			fi
		esac

	;;
	
	"restore" )	
		case $2 in
			"index" )
				restoreIndexes $1 $2 $3 $4
			;;
			"db" )
				restoreDb $1 $2 $3 $4
			;;
			"cs" )
				restoreContentStore $1 $2 $3 $4
			;;
			"files" )
				restoreFiles $1 $2 $3 $4
			;;
			"all" )
				restoreIndexes $1 $2 $3 $4
				restoreDb $1 $2 $3 $4
				restoreContentStore $1 $2 $3 $4
				restoreFiles $1 $2 $3 $4
			;;
			* )
			restoreWizard
		esac
   	
    ;;
    
	"verify" ) 
		verifyCommands $1 $2
	;;
    
	"list" ) 
    	listCommands $1 $2
    ;;
    
	"collection" )
		collectionCommands $1 $2
    ;;

	"arrikitaun" )
		echo "Have a nice day!"
    ;;
    
	* ) 	
		usage
	;;
esac

# Unload al security variables
unset PASSPHRASE
unset AWS_ACCESS_KEY_ID
unset AWS_SECRET_ACCESS_KEY
unset DBPASS
unset FTP_PASSWORD
unset REC_MYPASS
unset REC_PGPASS
unset REC_ORAPASS
unset PGPASSWORD
