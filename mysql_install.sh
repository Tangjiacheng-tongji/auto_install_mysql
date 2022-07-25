#!/bin/bash

#some elementary variables
log=/var/log/mysql_install.log
path=/tmp/
target_zip=mysql-5.7.32-linux-glibc2.12-x86_64.tar.gz
target_folder=`echo "$target_zip" | sed -e 's/.tar.gz//g'`
basedir=/usr/local
datadir=/data/mysql
passwd="123456"
link=0

usage(){
	cat<<EOF
Usage:$0 [OPTIONS]
  --path=/tmp/               	 Temporary folder to store binary files
  --basedir=/usr/local		 Address of MySQL file
  --link			 Use soft link
  --datadir=/data/mysql		 Address where data is stored
  --target_folder=mysql-5.7.32-linux-glibc2.12-x86_64
				 Target folder if already unzipped
  --target_zip=mysql-5.7.32-linux-glibc2.12-x86_64.tar.gz
 				 Compressed files downloaded/read
  --passwd=123456		 Reset database password
EOF
exit 1
}

parse_arguments() {
	for arg do
		val=`echo "$arg" | sed -e 's;^--[^=]*=;;'`
		optname=`echo "$arg" | sed -e 's/^\(--[^=]*\)=.*$/\1/'`
		optname_subst=`echo "$optname" | sed 's/_/-/g'`
   		arg=`echo $arg | sed "s/^$optname/$optname_subst/"`
		case "$arg" in
			--path=*) path="$val";;
			--basedir=*) basedir="$val";;
			--datadir=*) datadir="$val";;
			--target_folder=*) target_folder="$val";;
			--target_zip=*) target_zip="$val";;	
			--link) link=1;;
			--passwd=*) passwd="$val";;
	
			--help) usage ;;
		esac
	done
}

parse_arguments "$@"
touch $log
chmod 777 $log

if ps -aux|grep mysql > /dev/null
then
        echo "Process 'mysql' found, install anyway?(y/n)"
        read to_install
        if test "$to_install" = "n"
        then
        	exit 0
	else
		echo "Stop the process.."
		service mysql stop > /dev/null 2>&1
	fi
fi


has_user=`grep 'mysql' /etc/passwd | wc -l`
if test $has_user -ne 0
then
        echo "Find user mysql, add it again."
	if test `ps -u mysql|grep -c mysql` -ne 0
	then
        	PROC=`ps -u mysql|sed -n '$p'|awk '{print $1}'`
		for T in $PROC
		do
			kill -9 $T > /dev/null 2>&1
			if test $? -eq 0
			then
				echo "Pid $T killed."	
			else
				break
			fi
		done
	fi
	userdel mysql
fi

has_group=`grep 'mysql' /etc/group | wc -l`
if test $has_group -ne 0
then
	echo "Find group mysql, add it again."
	groupdel mysql
fi	
groupadd mysql
useradd -r -g mysql -s /bin/false mysql

basedir=$basedir/mysql
if test -d $basedir
then
	echo "Folder found: $basedir, install anyway?(y/n)"
	read to_install
	if test "$to_install" = "y"
        then
		rm -rf "$basedir"
	fi
fi

cd $path
if !(test -d $basedir)
then
	if test -d $path$target_folder
        then
                echo "Folder found: $target_folder"
        else
                echo "Can not find folder."
                if test -f $path$target_zip
               	then
                       	echo "Zip package found: $target_zip"
               	else
                       	echo "Can not find zip package."
                       	echo "Downloading $target_zip ..."
                       	wget "https://downloads.mysql.com/archives/get/p/23/file/$target_zip"
               	fi
               	tar zxvf $path$target_zip > $log 2>&1
               	target_folder=`echo "$target_zip" | sed -e 's/.tar.gz//g'`
	fi
fi



if test -d $datadir
then
        echo "Folder found: $datadir, remove and install again."
        rm -rf "$datadir"
fi

if test $link -eq 1
then
	echo "Making soft link: $path$target_folder -> $basedir"
	ln -s $path$target_folder "$basedir"
else
	echo "Moving folders: $path$target_folder ->  $basedir"
	mv $path$target_folder "$basedir"
fi

mkdir -p $datadir/{data,logs,tmp}

echo "Wrting configuration."
to_write=/etc/my.cnf
cat>$to_write<<EOF
[mysqld]
user=mysql
basedir=$basedir
datadir=$datadir/data
socket=$datadir/mysql.sock
port=3306
[client]
socket=$datadir/mysql.sock
[mysqld_safe]
EOF

if [ $? -ne 0 ]
then
	echo 'Failed to write the configuration file!'
	exit 1
fi

chown -R mysql:mysql $datadir
chmod 750 $datadir

echo "------------------------------"
echo "Initializing.."
chmod +x $basedir/bin/mysqld
$basedir/bin/mysqld --initialize >$log 2>&1

InitialPassword=`tail -1 $log |awk '{print $NF}'`

echo "Try to move the executable file: $basedir/support-files/mysql.server->/etc/init.d/mysql.server"
if test $link -eq 1
then
        cp $path$target_folder/support-files/mysql.server /etc/init.d/mysql.server
else
	cp $basedir/support-files/mysql.server /etc/init.d/mysql.server
fi
sed -i "46s;basedir=;basedir=$basedir;g" /etc/init.d/mysql.server
sed -i "47s;datadir=;datadir=$datadir/data;g" /etc/init.d/mysql.server
if [ $? -ne 0 ];then
	echo 'Failed to modified /etc/init.d/mysql.server!'
	exit 1
else
	echo 'Modified successfully!'
fi

chmod +x /etc/init.d/mysql.server

/etc/init.d/mysql.server start

$basedir/bin/mysql -uroot -p"$InitialPassword" --connect-expired-password -e "
alter user root@localhost identified by '$passwd';
flush privileges;
quit"

if test $? -ne 0
then
	echo "Fail to install."
else
	echo "-------------------------"
	echo "Install successfully, now you can login with the password"
	echo "-------------------------"
fi
