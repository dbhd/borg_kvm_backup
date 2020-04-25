#!/bin/bash

declare -a vmlist=("vm1" "vm2" "vm3")
declare -a vm1=("vda")
declare -a vm2=("vda" "vdb")
declare -a vm3=("vdb" "vdc")


SHCMD="$(basename -- $0)"
LOGS_DIR=/var/log/vm_backups
DATE="$(date +%Y%m%d_%H%M)"
LOG="$LOGS_DIR/vm_backups.$DATE.log"
# How many days to keep logs and qemu.xml files.
KEEP_FILES_FOR="14"
QEMU_XML_BACKUPS="/etc/libvirt/"
export BORG_PASSPHRASE='borg'
export BORG_REPO=root@hs.bhdr.ru:/st2/borgvm
borg_keep_daily="7"
borg_keep_weekly="4"
borg_keep_monthly="6"


#================================End Conf==================


[ ! -f $LOGS_DIR ] && mkdir -p $LOGS_DIR
echo "Starting backups on $HOSTNAME  $(date +'%d-%m-%Y %H:%M:%S')"  >> $LOG


for vm in "${vmlist[@]}"; do
    lst="$vm[@]"
    echo "========================" >> $LOG
    echo "Start Backup $vm with disk ${!lst}" >> $LOG
    if [[ $(virsh list | grep ${vm} | awk '{print $3}') != 'running' ]]; then
       echo "Skip backup - $vm not running" >> $LOG
      continue
    fi

# Все диски в виртуалке
    #arr1=${!lst}
    allvmdisk=$(virsh domblklist ${vm} | grep vd | awk '{print $1}')
    novmdisk=(`echo ${allvmdisk[@]} ${!lst} | tr ' ' '\n' | sort | uniq -u `)
#    echo "All disk in $vm :" ${allvmdisk[*]} >> $LOG
#    echo "Need disk in $vm :" ${!lst} >> $LOG
#    echo "No need disk in $vm :" ${novmdisk[*]} >> $LOG
# строка для снапшота необходимых дисков --diskspec $disk,file=${diskdir}/snapshot_${diskname}
    str1=""                                                                                                                                                                
    for disk in ${!lst}; do
      diskpath=$(virsh domblklist ${vm} | grep $disk | awk '{print $2}')
      diskdir=$(dirname "${diskpath}")
      diskname=$(basename "${diskpath}")
      str1+="--diskspec $disk,file=${diskdir}/snapshot_${diskname} "
    done
# строка для не нужных для снапшота дисков --diskspec vdb,snapshot=no
    for disk in ${novmdisk[@]}; do
      str1+="--diskspec $disk,snapshot=no "
    done

#Создаем снапшот виртуалки с учетом какие диски делаем какие нет
   CMD="virsh snapshot-create-as --domain ${vm} --name snapshot --no-metadata --disk-only --atomic --quiesce ${str1}"
   echo $CMD
   #echo "Command: $CMD" >> $LOG
   eval "$CMD" >> $LOG 2>&1
    if [ $? -ne 0 ]; then
     echo "Failed to create snapshot for $vm" >> $LOG
     continue
    fi

    for disk in "${!lst}"; do
# Где лежит диск
    diskpath=$(virsh domblklist ${vm} | grep $disk | awk '{print $2}')
    diskdir=$(dirname "${diskpath}")
    diskname=$(basename "${diskpath}")

#   echo "Copy to borg"
   CMD="borg create -v --stats $BORG_REPO::$vm-$disk-{now} $diskpath"
   echo $CMD
   #echo "Command: $CMD" >> $LOG
   eval "$CMD" >> $LOG 2>&1 
   if [ "$?" -ne "0" ]; then
     echo "Failed to create borg backup $vm $disk" >> $LOG
   fi

#   echo "Удаляем снапшот";
    CMD="virsh blockcommit $vm $disk --active --wait --pivot"
    echo $CMD
    #echo "Command: $CMD" >> $LOG
    eval "$CMD" >> $LOG 2>&1
    if [ "$?" -ne "0" ]; then
      echo "Failed blockcommit $vm $disk" >> $LOG
    fi

#   echo "Удаляем файл снапшота";
    CMD="rm -rf ${diskdir}/${diskname}"
    echo $CMD
    #echo "Command: $CMD" >> $LOG
    eval "$CMD" >> $LOG 2>&1
    if [ "$?" -ne "0" ]; then
      echo "Failed to remove snapshot file $vm ${diskname}" >> $LOG
     else
      echo "Succed remove snapshot file $vm ${diskname}" >> $LOG 
    fi
#Очистка репозитория borg в зависимости от виртуалок
   CMD="borg prune --dry-run --list --show-rc --prefix $vm-$disk --keep-daily $borg_keep_daily  --keep-weekly $borg_keep_weekly  --keep-monthly  $borg_keep_monthly"
   echo $CMD
   #echo "Command: $CMD" >> $LOG
   eval "$CMD" >> $LOG 2>&1
   if [ "$?" -ne "0" ]; then
     echo "Failed to prune borg backup for $BORG_REPO" >> $LOG
   fi


    done
done

#Копирую файлы xml виртуалок и сетей
   CMD="borg create -v --stats $BORG_REPO::libirt-conf-{now} $QEMU_XML_BACKUPS"
   echo $CMD
   #echo "Command: $CMD" >> $LOG
   eval "$CMD" >> $LOG 2>&1
   if [ "$?" -ne "0" ]; then
     echo "Failed to create borg backup for $QEMU_XML_BACKUPS" >> $LOG
   fi
#Очистка репозитория borg от libirt-conf
   CMD="borg prune --dry-run --list --show-rc --prefix libirt-conf --keep-daily $borg_keep_daily  --keep-weekly $borg_keep_weekly  --keep-monthly  $borg_keep_monthly"
   echo $CMD
   #echo "Command: $CMD" >> $LOG
   eval "$CMD" >> $LOG 2>&1
   if [ "$?" -ne "0" ]; then
     echo "Failed to prune borg backup for $BORG_REPO" >> $LOG
   fi


# Remove old log files
echo "Remove log files older than $KEEP_FILES_FOR days" >> $LOG
find $LOGS_DIR -maxdepth 1 -mtime +$KEEP_FILES_FOR -name "*.log" -exec rm -vf {} \; >> $LOG


#Отправка оповещение на емайл

