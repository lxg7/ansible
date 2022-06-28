#!/bin/bash

ROOT_UID=0 # Только пользователь с $UID 0 имеет привилегии root.
E_NOTROOT=67 # Признак отсутствия root-привилегий.


function choosedisk1 {
  
  # Идет выбор первого диска для raid массива. Может быть 
  # использован диск, на котором сейчас стоит система или новый диск.
  
  echo  -n "Будет ли текущий диск частью будущего массива?(y/n) "
  read def_disk_in_root
    
  case $def_disk_in_root in
  "y" | "Y" | "YES" | "yes" | "Yes" )
    echo "Текущий диск будет вхоить в систему..."
    disk1=`df | grep "/$" | awk '{print $1}'`
    echo "Текущий диск $disk1 выбран как первый в массиве"
    echo "Текущие параметры еще не поддерживаются..."
    exit 1 
  ;;
  
  "n" | "N" | "no" | "NO" | "No" )
    echo "Текущий диск не будет вхоить в систему..."
    echo "Введите название нового диска_1 дл массива(/dev/sdX)): "
    read disk1
    disk1_check=`echo $disk1 | tail -c 4`
    if [ $disk1_check == `lsblk | grep $disk1_check | awk '{print $1}'` ]
    then
      echo "Диск определен: $disk1"
    else
      echo "Ошибка! Нет такого диска..."
      exit 1
    fi
  ;;

  * )
    echo -n "unknown" ;;
  esac
}

function choosedisk2 {

  # Выбор второго диска для raid массива

  echo "Введите название нового диска_2 дл массива(/dev/sdX)): "
  read disk2
  disk2_check=`echo $disk2 | tail -c 4`
  if [ $disk2_check == `lsblk | grep $disk2_check | awk '{print $1}'` ]
  then
    echo "Диск определен: $disk2"
  else
    echo "Ошибка! Нет такого диска..."
    exit 1
  fi
  
}

function makeraid0 {
    echo "Выбран RAID-0."
    echo "В разработке..."
    exit 1
}

function makeraid1 {
echo  "Выбран RAID-1."
#choosedisk1
disk1=/dev/sdb
#choosedisk2
disk2=/dev/sdc
echo;echo
echo "====Форматирование дисков===="
echo;echo

echo "Форматирование диска $disk1"
# форматирование средствами mdadm, создание новой разметки диска, создание раздела на весь диск, установка флага raid autodetect
sudo mdadm --zero-superblock $disk1
parted -s $disk1 mklabel msdos
parted -s $disk1 mkpart primary 1MiB 100%
parted -s $disk1 set 1 raid on
disk11=`echo "$disk1"1`
 

echo "Форматирование диска $disk2"
# форматирование средствами mdadm, создание новой разметки диска, создание раздела на весь диск, установка флага raid autodetect
sudo mdadm --zero-superblock $disk2
parted -s $disk2 mklabel msdos
parted -s $disk2 mkpart primary 1MiB 100%
parted -s $disk2 set 1 raid on
disk21=`echo "$disk2"1`


echo;echo
echo "====Создание диска md0 - RAID-1 ===="
echo;echo
# создание массива md0 типа raid-1 из 2х устройств
yes | mdadm --verbose --create /dev/md0 --level=1 --raid-devices=2 $disk11 $disk21
# статистика по массиву
mdadm -D /dev/md0
# правка конфига для массива
echo "DEVICE partitions" > /etc/mdadm/mdadm.conf
mdadm --detail --scan --verbose | awk '/ARRAY/ {print}' >> /etc/mdadm/mdadm.conf



echo;echo
echo "====Разметка md0 + форматирование ===="
echo;echo
# перенос разделов старого диска на массив
sfdisk -d /dev/sda | sfdisk -f /dev/md0
# форматирование разделов массива в ext4 и swap 
mkfs.ext4 /dev/md0p1
mkswap /dev/md0p5


echo;echo
echo "====Перенос данных со старой системы===="
echo;echo
# монтирование массива и копирование всех файлов из текущей системы на массив
mount /dev/md0p1 /mnt
rsync -axu --info=progress2 / /mnt/


echo;echo
echo "====Меняем fstab на raid-системе===="
echo;echo
# замена UUID старых разделов в файле etc/fstab на новые (UUID разделов массива)
uuidsda1=`ls -l /dev/disk/by-uuid/ | grep sda1 | awk '{print $9}'`
uuidmd0p1=`ls -l /dev/disk/by-uuid/ | grep md0p1 | awk '{print $9}'`
sed "s/$uuidsda1/$uuidmd0p1/" -i /mnt/etc/fstab

uuidsda5=`ls -l /dev/disk/by-uuid/ | grep sda5 | awk '{print $9}'`
uuidmd0p5=`ls -l /dev/disk/by-uuid/ | grep md0p5 | awk '{print $9}'`
sed "s/$uuidsda5/$uuidmd0p5/" -i /mnt/etc/fstab


echo;echo;echo;echo;echo
echo "====chroot===="
# необходимо для работы в chroot
sudo mount --bind /proc /mnt/proc
sudo mount --bind /dev /mnt/dev
sudo mount --bind /sys /mnt/sys
sudo mount --bind /run /mnt/run


echo;echo;echo;echo;echo
echo "====Обновление конфигов grub и установка на новые диски===="
echo '====Переходим в новое окружение'
# копируем скрипт chroot.sh в /mnt для того, чтобы chroot нашел этот скрипт при изменении корневого каталога
sudo cp /tmp/raid/chroot.sh /mnt/chroot.sh 
# выполняем скрипт
sudo chroot /mnt/ /chroot.sh $disk1 $disk2
# cat /boot/grub/grub.cfg | grep UUID_нового_системного_раздела проверка меню grub
echo "chroot ok"
echo
echo "!!!RAID готов!!!"
echo

}

function inst_req {
  # Проверка наличия необходимых программ
  command -v mdadm >/dev/null 2>&1 || { echo >&2 "I require mdadm but it's not installed.  Aborting."; exit 1; }
  command -v parted >/dev/null 2>&1 || { echo >&2 "I require parted but it's not installed.  Aborting."; exit 1; }
  command -v rsync >/dev/null 2>&1 || { echo >&2 "I require rsync but it's not installed.  Aborting."; exit 1; }
  # command -v foo >/dev/null 2>&1 || { echo >&2 "I require foo but it's not installed.  Aborting."; exit 1; }
  echo "Все программы установлены (mdadm, parted, rsync)"

}

function root_check {
  if [ "$UID" -ne "$ROOT_UID" ]
  then
    echo "Для работы сценария требуются права root."
    exit $E_NOTROOT
  fi
  echo "Root - права получены"
}


function requirements {
  echo "  _____            _____ _____   ____        _ _     _           "; sleep .1
  echo " |  __ \     /\   |_   _|  __ \ |  _ \      (_) |   | |          "; sleep .1
  echo " | |__) |   /  \    | | | |  | || |_) |_   _ _| | __| | ___ _ __ "; sleep .1
  echo " |  _  /   / /\ \   | | | |  | ||  _ <| | | | | |/ _\` |/ _ \ '__|";sleep .1
  echo " | | \ \  / ____ \ _| |_| |__| || |_) | |_| | | | (_| |  __/ |   "; sleep .1
  echo " |_|  \_\/_/    \_\_____|_____/ |____/ \__,_|_|_|\__,_|\___|_|   "; sleep .1
  echo "                            ______                               "; sleep .1
  echo "  _             _          |______|                              "; sleep .1
  echo " | |           | |        |____  |                               "; sleep .1
  echo " | |__  _   _  | |_  ____ _   / /                                "; sleep .1
  echo " | '_ \| | | | | \ \/ / _\` | / /                                 ";sleep .1
  echo " | |_) | |_| | | |>  < (_| |/ /                                  "; sleep .1
  echo " |_.__/ \__, | |_/_/\_\__, /_/                                   "; sleep .1
  echo "         __/ |         __/ |                                     "; sleep .1
  echo "        |___/         |___/                                      "; sleep .1
  echo
  echo "--- Для работы необохдимо:"
  echo "---   1. Диск с MBR разметкой (разделы Авто - /home и swap)"
  echo "---   2. Пакеты mdadm, parted, rsync"
  echo "--- Пока работает только вариант с RAID-1 для двух новых дисков(без текущего)."
  echo
}


#sudo su
requirements
root_check
inst_req
makeraid1
echo -n "Enter RAID level(0,1): "
#read rraidlevel

#echo -n "Выбран $raidlevel : "

case $rraidlevel in

  RAID0 | raid0 | 0)
    #makeraid0
    echo "В разработке..."
	exit 1
	;;

  RAID1 | raid1 | 1)
    makeraid1
	exit 0
    ;;
	
  *)
    echo "Ошибка. Тип массива не распознан."
    ;;
esac


