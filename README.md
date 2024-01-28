# postgresql-install
Based on CentOS 7.9 and PostgreSQL 15, a one-click compilation and deployment of PostgreSQL

# 使用说明

新的一年准备学习学习PostgreSQL，虽然安装简单，但是有的时候可能做一些测试导致环境不能恢复正常。又不想每次都手动安装，现在官网也不提供通用的二进制包，不过好在PostgreSQL的源码包比较小，编译时间也不需要太久，为了方便自己偷懒，写了一个简单的shell。编写和调试期间又在处理其他事情，写的时候思路断断续续，所以脚本中有些地方不是很严谨，有兴趣的伙伴可以自己修改完善。

搭建环境是基于CentOS7.9和PostgreSQL15。最开始写的时候用的是Redhat，考虑到有时候自己的虚拟机直接联网下载依赖包，但是Redhat每次都要从官网获取，有时候网络不稳定导致部署依赖包都很慢，所以后来改为了CentOS7，方便修改国内yum源。

脚本提供网络访问yum仓库和本地挂载ISO的方式安装依赖、单机部署和流复制部署（两台主从）。脚本使用时需要把所有文件都放在当前目录下，默认当前目录作为工作目录，日志默认在当前目录下的pg_install.log。

使用`-u|--user`指定用户的时候，用户可以已经存在，如果不存在则会自动创建。在脚本执行的时候会将PostgreSQL源码解压在工作目录，如果需要指定不用的用户，需要手动将上次一次解压后的源码目录（默认postgresql-15.5）删除。

脚本执行日志默认输出工作目录下的 pg_install.log 文件，因为个人不喜欢执行操作的终端输出太多日志把操作记录冲掉，一般都会单独新开一个窗口查看日志，所以脚本的所有输出都重定向到日志文件中了，不在终端显示。

~~~bash
##可以使用[-h|--help]查看支持选项，--preview查看预的部分参数取值
[root@darkstar02 postgre_tmp]# ./install-simple.sh -h
work_dir is /postgre_tmp

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
        Specify the number of CPUs to be used during compilation, by default, it uses half of the current number of cores.
        If the number of CPU cores is less than 4, you need to manually specify the number of CPUs that can be used.
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
        
[root@darkstar02 postgre_tmp]# ./install-simple.sh -p --preview
work_dir is /postgre_tmp

    Debugging usage, preview parameters
    调试使用，预览参数设置
    g_pg_version=15
    g_pg_user=postgres
    g_iso_name=CentOS-7-x86_64-DVD-2009.iso
    g_pg_software=postgresql-15.5.tar.gz
    ## 是否需要配置yum
    g_yum_server=yes
    ## 切换用户，执行命令
    g_use_cpu_num=2
    g_db_port=5432
    ## 如果需要安装备库，在配置好免密之后还需要尝试一次登录，因为在第一次登录的时候会提示部分信息，会影响程序执行
    g_install_type=single
    g_standby_host=
    ## 安装目录 需要使用绝对路径
    g_install_dir=/software/postgresql/pg15
    ## 数据目录的上层目录 需要使用绝对路径
    g_base_dir=/software/postgresql
    ## 为防止存在多块网卡，前期直接指定eth0网卡绑定的ip，centos7默认网卡名eth0。如果有多块网卡，建议直接指定ip地址或者hostname
    g_primary_host=192.168.120.223
    g_cfg_parameters= --enable-debug --enable-cassert --enable-dtrace --with-python --with-perl  --with-openssl
~~~

**执行部署前的目录结构**

~~~shell
├── CentOS-7-x86_64-DVD-2009.iso 	## ISO
├── install-simple.sh 				## 安装脚本
├── postgresql-15.5.tar.gz 			## PostgreSQL源码压缩包
├── python3_pak 					## python3-devel 包，通过本地仓库源的时候需要使用
└── template 						## pg_hba.conf postgresql.conf 模板文件目录，可以自行修改参数
~~~



**执行部署之后的目录结构**

~~~shell
├── backup20240118-0000 			## 生成备份文件的目录
├── CentOS-7-x86_64-DVD-2009.iso 	## ISO
├── install-simple.sh  				## 安装脚本
├── pg_install.log 					## 日志文件
├── postgresql-15.5  				## PostgreSQL源码解压目录，不同用户安装PostgreSQL时需要先删除上一次生成的该目录
├── postgresql-15.5.tar.gz 			## PostgreSQL源码压缩包
├── python3_pak 					## python3-devel 包，通过本地仓库源的时候需要使用
└── template 						## pg_hba.conf postgresql.conf 模板文件目录，可以自行修改参数
~~~

# 工具下载

~~~bash
## 百度云
链接: https://pan.baidu.com/s/1JBchCrBKPTdrdmnOlopyCA?pwd=ms3t 提取码: ms3t 复制这段内容后打开百度网盘手机App，操作更方便哦 
--来自百度网盘超级会员v6的分享
## gitee 仅包含脚本
https://gitee.com/TheDarkStar/postgresql-install
~~~



# 参考用法

## 单机默认参数部署

~~~shell
## 可以不带任何参数直接运行，默认单机部署，使用--preview查看部分默认参数值
[root@darkstar02 postgre_tmp]# ./install-simple.sh
[root@darkstar02 postgre_tmp]# ./install-simple.sh --preview
work_dir is /postgre_tmp

    Debugging usage, preview parameters
    调试使用，预览参数设置
    g_pg_version=15
    g_pg_user=postgres
    g_iso_name=CentOS-7-x86_64-DVD-2009.iso
    g_pg_software=postgresql-15.5.tar.gz
    ## 是否需要配置yum
    g_yum_server=yes
    ## 切换用户，执行命令
    g_use_cpu_num=2
    g_db_port=5432
    ## 如果需要安装备库，在配置好免密之后还需要尝试一次登录，因为在第一次登录的时候会提示部分信息，会影响程序执行
    g_install_type=single
    g_standby_host=
    ## 安装目录 需要使用绝对路径
    g_install_dir=/software/postgresql/pg15
    ## 数据目录的上层目录 需要使用绝对路径
    g_base_dir=/software/postgresql
    ## 为防止存在多块网卡，前期直接指定eth0网卡绑定的ip，centos7默认网卡名eth0。如果有多块网卡，建议直接指定ip地址或者hostname
    g_primary_host=192.168.120.223
    g_cfg_parameters=
~~~

## 单机指定参数

~~~shell
## -p 的参数包括 -D -C -T  -Y -E -S，图省事可以直接-p，也可以单独指定某一个或者几个参数，单独指定参数的时候不能使用选项-p，否则-p会覆盖其他几个选项
[root@darkstar02 postgre_tmp]# ./install-simple.sh -p
[root@darkstar02 postgre_tmp]# ./install-simple.sh -p --preview
work_dir is /postgre_tmp

    Debugging usage, preview parameters
    调试使用，预览参数设置
    g_pg_version=15
    g_pg_user=postgres
    g_iso_name=CentOS-7-x86_64-DVD-2009.iso
    g_pg_software=postgresql-15.5.tar.gz
    ## 是否需要配置yum
    g_yum_server=yes
    ## 切换用户，执行命令
    g_use_cpu_num=2
    g_db_port=5432
    ## 如果需要安装备库，在配置好免密之后还需要尝试一次登录，因为在第一次登录的时候会提示部分信息，会影响程序执行
    g_install_type=single
    g_standby_host=
    ## 安装目录 需要使用绝对路径
    g_install_dir=/software/postgresql/pg15
    ## 数据目录的上层目录 需要使用绝对路径
    g_base_dir=/software/postgresql
    ## 为防止存在多块网卡，前期直接指定eth0网卡绑定的ip，centos7默认网卡名eth0。如果有多块网卡，建议直接指定ip地址或者hostname
    g_primary_host=192.168.120.223
    g_cfg_parameters= --enable-debug --enable-cassert --enable-dtrace --with-python --with-perl  --with-openssl
~~~



~~~shell
[root@darkstar02 postgre_tmp]# ./install-simple.sh -D 
[root@darkstar02 postgre_tmp]# ./install-simple.sh -D --preview
work_dir is /postgre_tmp

    Debugging usage, preview parameters
    调试使用，预览参数设置
    g_pg_version=15
    g_pg_user=postgres
    g_iso_name=CentOS-7-x86_64-DVD-2009.iso
    g_pg_software=postgresql-15.5.tar.gz
    ## 是否需要配置yum
    g_yum_server=yes
    ## 切换用户，执行命令
    g_use_cpu_num=2
    g_db_port=5432
    ## 如果需要安装备库，在配置好免密之后还需要尝试一次登录，因为在第一次登录的时候会提示部分信息，会影响程序执行
    g_install_type=single
    g_standby_host=
    ## 安装目录 需要使用绝对路径
    g_install_dir=/software/postgresql/pg15
    ## 数据目录的上层目录 需要使用绝对路径
    g_base_dir=/software/postgresql
    ## 为防止存在多块网卡，前期直接指定eth0网卡绑定的ip，centos7默认网卡名eth0。如果有多块网卡，建议直接指定ip地址或者hostname
    g_primary_host=192.168.120.223
    g_cfg_parameters= --enable-debug
~~~

## 流复制安装

流复制的部署前提是两台主机提前配置好root用户的免密，考虑安全的话可以在部署完成之后手动取消免密。最主要的参数就是`-s -t`，其他的参数和单机部署一样。

流复制部署的时候会简单校验两台服务器的时间，如果时间间隔超过5秒，需要先订正时间。

~~~shell
## 需要同时指定-s -t选项，如果仅指定-s选项，则只会在工作目录生成一个“.standby.cmd.*”文件，并不会自动部署备库
[root@darkstar02 postgre_tmp]# ./install-simple.sh -p -s"192.168.120.244" -t"hot_standby"
[root@darkstar02 postgre_tmp]# ./install-simple.sh -p -s"192.168.120.244" -t"hot_standby" --preview
[root@darkstar02 postgre_tmp]# bash install-simple.sh -p -b "/software/pgsql2" -d "/software/pgsql2/pg15"  -u"pguser2" -s"192.168.120.244" -t"hot_standby"

[root@darkstar02 postgre_tmp]# less pg_install.log

work_dir is /postgre_tmp
check time zone =================
darkstar02 timezone is Asia/Shanghai
start config yum ============
cmd_mount_iso = mount -o loop CentOS-7-x86_64-DVD-2009.iso /mnt
*******cmd_mount_iso: mount -o loop CentOS-7-x86_64-DVD-2009.iso /mnt*******
文件系统       类型      容量  已用  可用 已用% 挂载点
devtmpfs       devtmpfs  909M     0  909M    0% /dev
tmpfs          tmpfs     919M     0  919M    0% /dev/shm
tmpfs          tmpfs     919M  8.6M  911M    1% /run
tmpfs          tmpfs     919M     0  919M    0% /sys/fs/cgroup
/dev/sda3      xfs        27G  5.7G   22G   21% /
/dev/sda1      xfs      1014M  141M  874M   14% /boot
tmpfs          tmpfs     184M     0  184M    0% /run/user/0
。。。。
2024-01-18 00:11:46.877 CST [2380] HINT:  Future log output will appear in directory "pg_log".
 done
server started
Connection to 192.168.120.244 closed.
startup standby successful
   client_addr   | sync_state
-----------------+------------
 192.168.120.244 | async
(1 row)

end==========================

~~~

## 使用网络镜像仓库源编译安装

~~~shell
## -y no | --yum-server=no 表示联网安装依赖包
[root@darkstar02 postgre_tmp]# bash install-simple.sh  -b "/software/pgsql1" -d "/software/pgsql1/pg15"  -u"pguser1" -s"192.168.120.244" -t"hot_standby" -y no
~~~



# configure选项参考

更多编译选项请参考官网：[PostgreSQL: Documentation: 15: 17.4. Installation Procedure](https://www.postgresql.org/docs/15/install-procedure.html#CONFIGURE-OPTIONS)

- --prefix=*`PREFIX`*

  PostgreSQL安装目录，所有的安装文件存放在指定目录 PREFIX 而不是默认的 /usr/local/pgsql。实际文件将被安装到各个子目录中，PREFIX是安装文件的上层目录。

- --enable-debug

  开启debug，一般研究调试源码的时候开启，生产不需要打开。

- --enable-cassert

  在服务器中启用断言检查，用于测试许多“不应该发生”的情况。开发调试的阶段很有必要，但测试会显著降低服务器的性能。此外，启用测试并不一定会增强服务器的稳定性！断言检查未根据严重程度进行分类，因此，即使触发了断言失败，可能是一个相对无害的错误，也仍会导致服务器重新启动。不建议在生产环境中使用此选项，但在开发工作或运行测试版本时，建议启用它。

- --enable-dtrace

  启用PostgreSQL编译对动态跟踪工具 DTrace 的支持。

- --with-python

  开启PL/Python语言支持，开启之后可以在PostgreSQL中使用python编写存储函数之类的操作。

- --with-perl

  开启PL/Perl语言支持，开启之后可以在PostgreSQL中使用perl编写存储函数之类的操作。

- --with-openssl

  开启SSL（加密）连接支持。这个选项需要安装OpenSSL包。低版本使用的是`--with-ssl=openssl`。
