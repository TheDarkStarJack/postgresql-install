#!/bin/bash

#===============================================================================
#
#          FILE: install-simple.sh
#
#         USAGE: ./install-simple.sh -p 
#                ./install-simple.sh -p -s"192.168.120.244" -t"hot_standby"
#                ./install-simple.sh -b "/software/pgsql1" -d "/software/pgsql1/pg15"  -u"pguser1" -s"192.168.120.244" -t"hot_standby" -y no
#                ./install-simple.sh -p -b "/software/pgsql1" -d "/software/pgsql1/pg15"  -u"pguser1" -s"192.168.120.244" -t"hot_standby" 
#
#   DESCRIPTION: PostgreSQL install
#
#       OPTIONS: ---
#  REQUIREMENTS: ---
#          BUGS: ---
#         NOTES: ---
#        AUTHOR: wxj (TheDarkStar), 2403220952@qq.com
#  ORGANIZATION: 
#       CREATED: 2024/1/16 18:03:55
#      REVISION:  ---
#===============================================================================
## 所有操作都在root用户操作，所有文件都放在当前目录
# 检查是否以root权限运行
if [[ $EUID -ne 0 ]]; then
    echo "Please use root user to execute the script"
    exit 1
fi

handle_error() {
    echo "Installation failed. You can restore the configuration file based on the backup directory $g_backup_dir "
    echo "You can restore the original configuration based on the files in the backup directory, clean the compilation directory, and then re execute it"
    exit 1
}

trap 'handle_error' ERR

fun_usage() {
    echo '
    Usage: pg_install [OPTION]... [FILE]...
    -v|--install-version
        PostgreSQL version
    -f|--software
        PostgreSQL software file
    -u|--user
        PostgreSQL user,default postgres,passwd is "DarkStar007"
    -i|--cdrom
        ISO file.If the parameter "-y=yes", then this parameter will be ignored.
    -y|--yum-server
        default yes.If the value is no, it means that there is no need to configure the software repository and the server can access the internet
    -P|--port
        database server port (default: "5432")
    -t|--install-type
        single/hot_standby
    -h|--help
        get help
    --preview
        Debugging usage, preview parameters,Unable to execute program
    -c|--cpu-num
        Specify the number of CPUs to be used during compilation. By default, it utilizes half of the current number of cores
        if the CPU core count is greater than or equal to 4; otherwise, it defaults to using 2 CPU cores.
        Of course, you can also manually specify the number of CPU cores for compilation.
    -p|--parameters
        default "--enable-debug --enable-cassert --enable-dtrace --with-python --with-perl  --with-openssl "
    -D|--pg-debug
        default --enable-debug = yes.If the parameter -p is specified, it will be ignored
    -C|--pg-cassert
        default --enable-cassert = yes.If the parameter -p is specified, it will be ignored
    -T|--pg-dtrace
        default --enable-dtrace = yes.If the parameter -p is specified, it will be ignored
    -Y|--pg-python
        default --with-python = yes.If the parameter -p is specified, it will be ignored
    -E|--pg-perl
        default --with-perl = yes.If the parameter -p is specified, it will be ignored
    -S|--pg-openssl
        default --with-openssl = yes.If the parameter -p is specified, it will be ignored
    -m|--primary-host
        Hostname or IP address of the primary database. The default IP address bound to the eth0 network interface card.
    -s|--standby-host
        Hostname or IP address of the standby database.
    -d|--install-directory
        The installation directory for PostgreSQL
    -b|--pgbase=basedir
        location of the database storage area ,incluede {data,backup,archive,scripts ....}
    '
}


## 备份；回退。是否备份，是否回退；输出整个安装概览

## 配置镜像源
fun_config_yum() {
    echo "start config yum ============"
    # mkdir -pv iso_dir
    if test -f "$g_iso_name"; then
        ##mv $g_iso_name CentOS7.iso
        cmd_mount_iso="mount -o loop $g_iso_name /mnt"
        echo "cmd_mount_iso = $cmd_mount_iso "
    else
        echo "Please check if the $g_iso_name file exists "
        exit 1
    fi

    echo "*******cmd_mount_iso: $cmd_mount_iso*******"
    df -hT
    umount /mnt
    if ! ${cmd_mount_iso} &>/dev/null; then
        echo "ERROR: mount -o loop $g_iso_name /mnt failed,please check"
        exit 1
    else
        echo "File $g_iso_name successfully mounted "
        #umount /mnt
    fi

    ## 备份仓库目录
    repo_bak="$g_backup_dir/repo_bak"
    if ! mkdir -pv "$repo_bak"; then
        echo "mkdir $repo_bak failed "
        exit 1
    fi

    mv /etc/yum.repos.d/*.repo "$repo_bak"

    cat >>/etc/yum.repos.d/local.repo <<-EOFWXJ
[local]
name=Local repo
baseurl=file:///mnt
enabled=1
gpgcheck=0
EOFWXJ

}

## 安装依赖
fun_yum_install() {
    echo "start install packages ================"
    #yum update 1>/dev/null
    yum clean all 1>/dev/null
    yum makecache 1>/dev/null
    yum_install_cmd="yum -y install readline readline-devel zlib zlib-devel systemtap-sdt-devel \
gettext gettext-devel openssl openssl-devel pam pam-devel \
libxml2 libxml2-devel libxslt libxslt-devel perl perl-devel \
tcl-devel uuid-devel gcc gcc-c++ make flex bison perl-ExtUtils* \
vim net-tools unzip zip  net-tools lrzsz vim sysstat dstat bc tree expect psmisc bzip2 \
python3 "
    if test "$g_yum_server" = "no"; then
        yum_install_cmd="$yum_install_cmd  python3-devel "
    fi

    if test $(rpm -qa | grep python3-devel | wc -l) -eq 0; then
        echo "install python3-devel "
        rpm -i "$g_work_dir"/python3_pak/*rpm
    fi

    if $yum_install_cmd; then
        echo "install package is successful"
    else
        echo "install package is failed, please check log"
    fi

}
## 创建用户；或者指定用户
fun_createUser() {
    echo "start create user ==========="
    #username="postgres"
    if id "$g_pg_user" &>/dev/null; then
        echo "user $g_pg_user is exist "
    else
        echo "creaet user $g_pg_user"
        user_mark=0
        useradd -rm "$g_pg_user" -s "/bin/bash"
        tmp_passwd="DarkStar007"
        echo "$tmp_passwd" | passwd --stdin "$g_pg_user"
        if test -n "$g_standby_cmd" && test $user_mark -eq 0; then
            echo "# creaet user $g_pg_user"
            echo "useradd -rm $g_pg_user -s \"/bin/bash\""
            echo "echo \"$tmp_passwd\" | passwd --stdin $g_pg_user"
        fi >>"$g_stanby_cmd_file01"
    fi

}

## 关闭防火墙 selinux
fun_stop_firewalld_and_selinux() {
    echo "stop firewalld =========="
    systemctl status firewalld
    systemctl stop firewalld.service
    systemctl disable firewalld.service
    if cp /etc/selinux/config /etc/selinux/config.bak"$g_date"; then
        sed -i "s/SELINUX=enforcing/SELINUX=disabled/" /etc/selinux/config
        setenforce 0
    fi

    if test -n "$g_standby_cmd"; then
        echo "
    systemctl status firewalld
    systemctl stop firewalld.service
    systemctl disable firewalld.service
    cp /etc/selinux/config /etc/selinux/config.bak$g_date
    sed -i \"s/SELINUX=enforcing/SELINUX=disabled/\" /etc/selinux/config
    setenforce 0
    "
    fi >>"$g_stanby_cmd_file01"
}

## 创建目录
fun_mkdir() {
    echo "mkdir any dir ============="
    ## 如果没有指定目录，默认目录取值，该变量需要为全局变量，也不需要提前创建
    ## 源码目录默认为当前目录 pwd
    ## install_dir="/software/postgresql/pg15"
    if test ! -d "$g_install_dir"; then
        mkdir -pv "$g_install_dir"
        chown -R "$g_pg_user":"$g_pg_user" $g_install_dir
    else
        if test $(ls -lA $g_install_dir | awk '{print $2}' | head -1) -eq 0; then
            echo "$g_install_dir is not empty,please check"
            exit 1
        else
            chown -R "$g_pg_user":"$g_pg_user" $g_install_dir
        fi
    fi
    ## 如果目录存在，则判断目录的所有者是否是安装pg的用户
    # base_dir="/software/postgresql"
    ## 数据目录
    mkdir -pv "$g_base_dir"/data && chown -R "$g_pg_user":"$g_pg_user" "$g_base_dir"/data

    if test -n "$g_standby_cmd"; then
        echo "
        mkdir -pv $g_install_dir
        chown -R $g_pg_user:$g_pg_user $g_install_dir
        mkdir -pv $g_base_dir/data && chown -R $g_pg_user:$g_pg_user $g_base_dir/data
        chmod 0700 $g_base_dir/data
        "
    fi >>"$g_stanby_cmd_file01"
}

## 编辑参数（参数模板）；修改内核参数
fun_modifiy_sysctl() {
    echo "modifiy sysctl.conf and limit.conf =============="
    mark_string='for_pg_limit_by_wxj'
    if test $(grep -c $mark_string /etc/sysctl.conf) -eq 0; then
        cp /etc/sysctl.conf "$g_backup_dir"/sysctl.conf."$g_backup_suffix"
        mem_total=$(grep MemTotal /proc/meminfo | awk '{print $2}')
        cat >>/etc/sysctl.conf <<-EOFWXJ
#$mark_string
fs.file-max = 76724200
kernel.sem = 10000 10240000 10000 1024
kernel.shmmni = 4096
kernel.shmall = $mem_total
kernel.shmmax = $(echo "$mem_total"*1024 | bc)
net.ipv4.ip_local_port_range = 9000 65500
net.core.rmem_default = 262144
net.core.wmem_default = 262144
net.core.rmem_max = 4194304
net.core.wmem_max = 1048576
fs.aio-max-nr = 40960000
vm.dirty_ratio=20
vm.dirty_background_ratio=3
vm.dirty_writeback_centisecs=100
vm.dirty_expire_centisecs=500
vm.swappiness=10
vm.min_free_kbytes=524288
vm.overcommit_memory=2
vm.overcommit_ratio=75
net.ipv4.ip_local_port_range = 10000 65535
EOFWXJ
        sysctl -p
    fi

    if test $(grep -c $mark_string /etc/security/limits.conf) -eq 0; then
        cp /etc/security/limits.conf "$g_backup_dir"/limits.conf."$g_backup_suffix"
        cat >>/etc/security/limits.conf <<EOFWXJ
#$mark_string
$g_pg_user soft nofile 1048576
$g_pg_user hard nofile 1048576
$g_pg_user soft nproc 131072
$g_pg_user hard nproc 131072
$g_pg_user soft stack 10240
$g_pg_user hard stack 32768
$g_pg_user soft core 6291456
$g_pg_user hard core 6291456
EOFWXJ

        cat /etc/security/limits.conf
    fi

    if test -n "$g_standby_cmd"; then
        echo "scp $g_primary_host:/etc/sysctl.conf /etc/"
        echo "scp $g_primary_host:/etc/security/limits.conf /etc/security/"
        echo "sysctl -p"
    fi >>"$g_stanby_cmd_file01"
}

## 设置时间
fun_check_time() {
    echo "check time zone ================="
    # 为方便管理时区统一设置为 Asia/Shanghai
    host_tz=$(timedatectl | grep "Time zone" | awk '{print $3}')
    if test "${host_tz}" != "Asia/Shanghai"; then
        echo "error: $(hostname) timezone not Asia/Shanghai"
        if test -n "$g_standby_cmd"; then
            echo "# set time zone"
            echo "timedatectl set-timezone Asia/Shanghai"
        fi >>"$g_stanby_cmd_file01"
        exit 1
    else
        echo "$(hostname) timezone is $host_tz"
        sleep 2
    fi
    ## 检查两台服务器的时间差，超过5s提示
    local_time=$(date +%s)
    remote_time=$(ssh "$g_standby_host" "date +%s")
    time_difference=$((remote_time - local_time))

    if test $time_difference -ge 5 || test $time_difference -le -5; then
        echo "The time interval between server $g_primary_host and server $g_standby_host exceeds 5 seconds. Please synchronize the time between the servers."
        exit 1
    fi

}

## 编译
fun_cfg_build() {
    echo "start building"
    # 解压软件包
    software_suffix=".tar.gz"
    if ! test "${g_pg_software: -7}" = "$software_suffix"; then
        echo "Currently, only compressed packages in tar.gz format are supported,please check software."
        echo "wget https://ftp.postgresql.org/pub/source/v15.5/postgresql-15.5.tar.gz "
        exit 1
    fi
    tar_cmd="tar zxf $g_pg_software "
    string_length=${#g_pg_software}
    last_n_chars=7 # .tar.gz
    tar_dir=${g_pg_software:0:string_length-last_n_chars}
    #tar_dir="postgresql-15.5"
    prefix_dir="--prefix='$g_install_dir'"
    cfg_parameter=$g_cfg_parameters
    if $tar_cmd; then
        if test -d "$tar_dir"; then
            chown -R "$g_pg_user":"$g_pg_user" "$tar_dir"
        else
            echo "$tar_dir directory does not exist, please check $tar_cmd "
            exit 1
        fi
    else
        echo "Failed to decompress file "
        exit 1
    fi
    cd "$tar_dir" || exit 1
    $g_su_user_cmd " ./configure $prefix_dir $cfg_parameter"
    if test $? -eq 0; then
        echo "configure successful"
    else
        echo "configure failed"
        exit 1
    fi
    os_cpu_core_number=$(grep -c processor /proc/cpuinfo)
    ## 默认使用cpu的数量
    use_cpu=$g_use_cpu_num
    can_use_cpu=$(echo "$os_cpu_core_number" / 2 | bc)
    if test "$can_use_cpu" -ge "$use_cpu"; then
        use_cpu=$(("$os_cpu_core_number" / 2))
        $g_su_user_cmd " make -j $use_cpu && make install"
        echo ""
    else
        $g_su_user_cmd " make -j $use_cpu && make install"
    fi
    pg_version=$("$g_install_dir"/bin/postgres --version)
    if test $? -ne 0; then
        echo "ERROR: software install fail,please check install log"
        exit 1
    else
        echo "$pg_version software install complete!"
        echo "start init $pg_version"
        $g_su_user_cmd "$g_install_dir/bin/initdb -D $g_base_dir/data -E UTF8 --locale=en_US.utf8 -U $g_pg_user"
        if test $? -ne 0; then
            echo "ERROR: initdb fail,please check install log"
            exit 1
        fi
    fi

    if test -n "$g_standby_cmd"; then
        echo "
        mkdir -pv ${g_work_dir}
        scp -rp $g_primary_host:${g_work_dir}/${tar_dir} ${g_work_dir}/${tar_dir}
        chown -R $g_pg_user:$g_pg_user ${g_work_dir}/${tar_dir}
        ## 更换目录，避免su user的时候在/root目录。提示could not change directory to /root: 权限不够
        cd ${g_work_dir}/${tar_dir}
        $g_su_user_cmd \"make install\"
        if test \$? -eq 0;then
           echo \"standby install successful \"
           else
           echo \"standby install failed , please check logfile $install_log \"
           exit 1
        fi
        "
    fi >>"$g_stanby_cmd_file01"

    ## 修改主库conf
    $g_su_user_cmd "cp $g_base_dir/data/pg_hba.conf $g_base_dir/data/pg_hba.conf$g_backup_suffix"
    $g_su_user_cmd "cp $g_base_dir/data/postgresql.conf $g_base_dir/data/postgresql.conf$g_backup_suffix"
    $g_su_user_cmd "cp $g_work_dir/template/template_pg_hba.conf $g_base_dir/data/pg_hba.conf"
    $g_su_user_cmd "cp $g_work_dir/template/template_postgresql.conf $g_base_dir/data/postgresql.conf"
}

## 9、启动数据库，创建用户
fun_startdb() {
    echo "start db ========="
    PGDATA="$g_base_dir"/data

    if test -n "$g_standby_cmd"; then
        echo "
        $g_su_user_cmd \"export PGPASSWORD='DarkStarRep01';$g_install_dir/bin/pg_basebackup -h $g_primary_host -U replicator -w  -F p -P -X stream -R -D $PGDATA -l repbackup$g_date \"
        # 经过测试，如果在脚本内部执行启动数据库的命令，tee还是无法正常结束进程
        #$g_su_user_cmd \"$g_install_dir/bin/pg_ctl start -D $PGDATA \"
        # if test \$? -eq 0;then
        #    exit 0
        # fi
    "
    fi >>"$g_stanby_cmd_file01"
    $g_su_user_cmd "$g_install_dir/bin/pg_ctl start -D $PGDATA "
    if test $? -eq 0; then
        echo "start db succeed"
        echo "$g_su_user_cmd \"$g_install_dir/bin/pg_ctl start -D $PGDATA\""
        echo "$g_su_user_cmd \"$g_install_dir/bin/pg_ctl stop -D $PGDATA\""
        if test -n "$g_standby_host"; then
            $g_su_user_cmd "$g_install_dir/bin/psql -p $g_db_port -d postgres -q -c \"create user replicator replication login connection limit 5 password 'DarkStarRep01';\""
            echo "created user replicator "
        fi
    else
        echo "start db failed . please check $install_log !"
        exit 1
    fi

}

## 备库操作
fun_standby() {
    echo "standby db ========="
    $g_standby_cmd <"$g_stanby_cmd_file01"
    $g_standby_cmd "cd /tmp ;$g_su_user_cmd '$g_install_dir/bin/pg_ctl start -D $PGDATA' "
    if test $? -eq 0; then
        echo "startup standby successful"
    else
        echo "startup standby  failed,please check log"
        exit 1
    fi

}

## 检查主从复制
fun_check_replication() {
    $g_su_user_cmd "$g_install_dir/bin/psql -p $g_db_port -d postgres -q -c 'select client_addr,sync_state from pg_stat_replication ;'"
}

main() {
    g_work_dir=$(pwd)
    if ! test -e "$0"; then
        echo "Please place all files in the directory where the executable script is located and execute the script in the directory "
        exit 1
    else
        echo "work_dir is $g_work_dir"
    fi

    ## 时间
    g_date=$(date +"%Y%m%d-%H%M")
    g_backup_dir="backup$g_date"
    g_backup_suffix="bak$g_date"
    if test -d g_backup_dir; then
        if ! mkdir -v "$g_backup_dir"; then
            echo "mkdir $g_backup_dir failed,please check"
        fi
    fi

    ## stanby cmd file
    g_stanby_cmd_file01="$g_work_dir/.standby.cmd.$g_date"

    g_pg_version=15
    g_pg_user="postgres"
    g_iso_name="CentOS-7-x86_64-DVD-2009.iso"
    g_pg_software="postgresql-15.5.tar.gz"
    ## 是否需要配置yum
    g_yum_server="yes"
    ## 切换用户，执行命令
    g_su_user_cmd="su $g_pg_user  -c "
    g_use_cpu_num=2
    g_cfg_parameters=''
    g_db_port="5432"
    ## 如果需要安装备库，在配置好免密之后还需要尝试一次登录，因为在第一次登录的时候会提示部分信息，会影响程序执行
    g_install_type="single" ## 需要判断安装类型和备库两个参数要检验，避免冲突
    g_standby_host=""
    ## 安装目录 需要使用绝对路径
    g_install_dir="/software/postgresql/pg$g_pg_version"
    ## 数据目录的上层目录 需要使用绝对路径
    g_base_dir="/software/postgresql"
    ## 为防止存在多块网卡，前期直接指定
    g_primary_host=$(ip addr show eth0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}')

    g_parameters=$(getopt -o v:f:u:i:y:P:t:c:pDCTYESm:s:d:b:h --long install-version:,software:,user:,cdrom:,yum-server:,port:,install-type:,cpu-num:,parameters,pg-debug,pg-cassert,pg-dtrace,pg-python,pg-perl,pg-openssl:,primary-host:,standby-host:,install-directory:,pgbase:,help,preview -n "$0" -- "$@")
    if test $? -ne 0; then
        echo "Terminating..."
        exit 1
    fi
    eval set -- "$g_parameters"

    while true; do
        case "$1" in
        -v | --install-version)
            g_pg_version="$2"
            shift 2
            ;;
        -f | --software)
            g_pg_software="$2"
            shift 2
            ;;
        -u | --user)
            g_pg_user="$2"
            g_su_user_cmd="su $g_pg_user  -c "
            shift 2
            ;;
        -i | --cdrom)
            if test "$g_yum_server" -eq "no"; then
                unset g_iso_name
                echo "The option - y no or -- yum server=no has been specified, and the - i | -- cdrom option will be ignored and will not be used to configure the local software repository source"
            else
                g_iso_name="$2"
            fi
            shift 2
            ;;
        -y | --yum-server)
            g_yum_server="$2" && unset g_iso_name
            shift 2
            ;;
        -P | --port)
            g_db_port="$2"
            shift 2
            ;;
        -t | --install-type)
            g_install_type="$2"
            shift 2
            ;;
        -c | --cpu-num)
            g_use_cpu_num="$2"
            shift 2
            ;;
        -p | --parameters)
            if test -z "$g_cfg_parameters"; then
                g_cfg_parameters=" --enable-debug --enable-cassert --enable-dtrace --with-python --with-perl  --with-openssl "
                readonly g_cfg_parameters
            else
                unset g_cfg_parameters
                g_cfg_parameters=" --enable-debug --enable-cassert --enable-dtrace --with-python --with-perl  --with-openssl "
                readonly g_cfg_parameters
                echo "The parameter -p has been specified, and the -D 、-C、-T、-Y、-E、-S parameter will be ignored"
            fi
            shift 1
            ;;
        -D | --pg-debug)
            g_cfg_parameters=$g_cfg_parameters" --enable-debug " &>/dev/null
            if test $? != 0; then
                echo "The parameter -p has been specified, and the -D parameter will be ignored"
            fi
            shift 1
            ;;
        -C | --pg-cassert)
            g_cfg_parameters=$g_cfg_parameters" --enable-cassert " &>/dev/null
            if test $? != 0; then
                echo "The parameter -p has been specified, and the -C parameter will be ignored"
            fi
            shift 1
            ;;
        -T | --pg-dtrace)
            g_cfg_parameters=$g_cfg_parameters" --enable-dtrace " &>/dev/null
            if test $? != 0; then
                echo "The parameter -p has been specified, and the -T parameter will be ignored"
            fi
            shift 1
            ;;
        -Y | --pg-python)
            g_cfg_parameters=$g_cfg_parameters" --with-python " &>/dev/null
            if test $? != 0; then
                echo "The parameter -p has been specified, and the -Y parameter will be ignored"
            fi
            shift 1
            ;;
        -E | --pg-perl)
            g_cfg_parameters=$g_cfg_parameters" --with-perl " &>/dev/null
            if test $? != 0; then
                echo "The parameter -p has been specified, and the -E parameter will be ignored"
            fi
            shift 1
            ;;
        -S | --pg-openssl)
            g_cfg_parameters=$g_cfg_parameters" --with-openssl " &>/dev/null
            if test $? != 0; then
                echo "The parameter -p has been specified, and the -S parameter will be ignored"
            fi
            shift 1
            ;;
        -m | primary-host)
            g_primary_host="$2"
            shift 2
            ;;
        -s | --standby-host)
            g_standby_host="$2"
            ## standby
            g_standby_cmd="ssh $g_standby_host -t "
            if ! $g_standby_cmd "date" &>/dev/null; then
                echo "Unable to connect to the remote server. Please check your network connection or configure passwordless login. "
                exit 1
            fi
            shift 2
            ;;
        -d | --install-directory)
            g_install_dir="$2"
            shift 2
            ;;
        -b | --pgbase)
            g_base_dir="$2"
            shift 2
            ;;
        --preview)
            echo "
    Debugging usage, preview parameters
    调试使用，预览参数设置
    g_pg_version=$g_pg_version
    g_pg_user=$g_pg_user
    g_iso_name=$g_iso_name
    g_pg_software=$g_pg_software
    ## 是否需要配置yum
    g_yum_server=$g_yum_server
    ## 切换用户，执行命令
    g_use_cpu_num=$g_use_cpu_num
    g_db_port=$g_db_port
    ## 如果需要安装备库，在配置好免密之后还需要尝试一次登录，因为在第一次登录的时候会提示部分信息，会影响程序执行
    g_install_type=$g_install_type
    g_standby_host=$g_standby_host
    ## 安装目录 需要使用绝对路径
    g_install_dir=$g_install_dir
    ## 数据目录的上层目录 需要使用绝对路径
    g_base_dir=$g_base_dir
    ## 为防止存在多块网卡，前期直接指定eth0网卡绑定的ip，centos7默认网卡名eth0。如果有多块网卡，建议直接指定ip地址或者hostname
    g_primary_host=$g_primary_host
    g_cfg_parameters=$g_cfg_parameters
    "
            exit 0
            ;;
        -h | --help)
            fun_usage
            exit 0
            ;;
        --)
            shift
            break
            ;;
        *)
            echo "unknow parameter: $1"
            exit 1
            ;;
        esac
    done

    g_install_run_log="pg_install.log"
    exec &>$g_install_run_log
    echo -n >"$g_stanby_cmd_file01"
    if test "$g_install_type" = "hot_standby"; then
        fun_check_time
    fi
    if test "$g_yum_server" = "yes"; then
        fun_config_yum
    fi

    fun_yum_install
    fun_stop_firewalld_and_selinux
    fun_createUser
    fun_mkdir
    fun_modifiy_sysctl
    fun_cfg_build
    fun_startdb
    if test "$g_install_type" = "hot_standby"; then
        fun_standby
        fun_check_replication
        rm -f "$g_stanby_cmd_file01"
    fi
    echo "end=========================="

}

main "$@"
