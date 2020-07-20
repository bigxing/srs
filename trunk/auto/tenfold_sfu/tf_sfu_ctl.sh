#!/usr/bin/env bash

PREFIX="/home/admin/tenfold-sfu"
BIN="$PREFIX/objs/tf_sfu"
CONF="$PREFIX/conf/app.conf"
DEFAULT_LOG_FILE="$PREFIX/logs/tf_sfu_start.log"
DEFAULT_PID_FILE="$PREFIX/objs/tf_sfu.pid"

########################################################################
# utility functions
########################################################################
RED="\\033[31m"
GREEN="\\033[32m"
YELLOW="\\033[33m"
BLACK="\\033[0m"
POS="\\033[60G"

ok_msg() {
    echo -e "${1}${POS}${BLACK}[${GREEN}    OK    ${BLACK}]"
}

failed_msg() {
    echo -e "${1}${POS}${BLACK}[${RED}FAILED${BLACK}]"
}

# load process info of tf_sfu
# @set variable $tf_sfu_pid to the process id in tf_sfu.pid file.
# @return 0, if process exists; otherwise:
#         1, for pid file not exists.
#         2, for get process info by pid failed.
# @set variable $error_msg if error.
# @set variable $pid_file to pid file.
load_process_info() {
    # get pid file
    pid_file=`cd ${PREFIX} && cat ${CONF} |grep ^pid|awk '{print $2}'|awk -F ';' '{print $1}'`
    if [[ -z $pid_file ]]; then pid_file=${DEFAULT_PID_FILE}; fi
    # get abs path
    pid_dir=`dirname $pid_file`
    pid_file=`(cd ${ROOT}; cd $pid_dir; pwd)`/`basename $pid_file`

    tf_sfu_pid=`cat $pid_file 2>/dev/null`
    ret=$?; if [[ 0 -ne $ret ]]; then error_msg="file $pid_file does not exists"; return 1; fi

    ps -p ${tf_sfu_pid} >/dev/null 2>/dev/null
    ret=$?; if [[ 0 -ne $ret ]]; then error_msg="process $tf_sfu_pid does not exists"; return 2; fi
    
    return 0
}

start() {
    #if exists, exit;
    load_process_info
    if [[ 0 -eq $? ]]; then failed_msg "tf_sfu started(pid ${tf_sfu_pid}), should not start it again."; return 1; fi

    # not exists, start server
    ok_msg "Starting Tenfold SFU..."

    # get log file
    log_file=`cd ${PREFIX} && cat ${CONF} |grep ^log_file|awk '{print $2}'|awk -F ';' '{print $1}'`
    if [[ -z $log_file ]]; then log_file=${DEFAULT_LOG_FILE}; fi
    # get abs path
    log_dir=`dirname $log_file`
    log_file=`(cd ${PREFIX} && cd $log_dir && pwd)`/`basename $log_file`

    # TODO: FIXME: set limit by, for instance, "ulimit -HSn 10000"
    if [[ -z $log_file ]]; then
        (ulimit -c ulimited && cd ${PREFIX}; ${BIN} -c ${CONF} >/dev/null 2>&1)
    else
        (ulimit -c ulimited && cd ${PREFIX}; ${BIN} -c ${CONF} >> $log_file.sys 2>&1)
    fi

    # check again after start server
    for((i = 0; i < 5; i++)); do
        # sleep a little while, for srs may start then crash.
        sleep 0.1
        load_process_info
        ret=$?; if [[ 0 -ne $ret ]]; then
            failed_msg "tf_sfu start failed";
            failed_msg "see $log_file";
            return $ret;
        fi
    done

    # check whether started.
    load_process_info
    ret=$?; if [[ 0 -eq $ret ]]; then ok_msg "tf_sfu started(pid ${tf_sfu_pid})"; return 0; fi

    failed_msg "tf_sfu not started."
    return $ret
}

stop() {
    # not start, exit;
    load_process_info
    if [[ 0 -ne $? ]]; then failed_msg "tf not start."; return 0; fi

    ok_msg "Stopping tf_sfu(pid ${tf_sfu_pid}"

    # process exists, try to kill to stop normally
    for((i = 0; i < 100; i++)); do
        load_process_info
        if [[ 0 -eq $? ]]; then
            kill -s SIGTERM ${tf_sfu_pid} 2>/dev/null
            ret=$?; if [[ 0 -ne $ret ]]; then failed_msg "send signal SIGTERM failed ret=$ret"; return $ret; fi
            sleep 0.3
        else
            ok_msg "tf_sfu stopped by SIGTERM"
            # delete the pid file when stop success
            rm -f ${pid_file}
            break;
        fi
    done

    # process exists, use kill -9 to force to exit
    load_process_info
    if [[ 0 -eq $? ]]; then
        kill -s SIGKILL ${tf_sfu_pid} 2>/dev/null
        ret=$?; if [[ 0 -ne $ret ]]; then failed_msg "send signal SIGKILL failed ret=$ret"; return $ret; fi
        ok_msg "tf_sfu stopped by SIGKILL"
    else
        # delete the pid file when stop success.
        rm -f ${pid_file}
    fi

    sleep 0.1
    return 0
}

# get the status of tf_sfu process
# @return 0 if tf_sfu is running; otherwise, 1 for stopped.
status() {
    load_process_info
    ret=$?; if [[ 0 -eq $ret ]]; then echo "tf_sfu(pid ${tf_sfu_pid}) is running."; return 0; fi

    echo "tf_sfu is stopped, $error_msg"
    return 1
}

reload() {
    # not start, exit
    load_process_info
    if [[ 0 -ne $? ]]; then failed_msg "tf_sfu not start."; return 0; fi

    ok_msg "reload tf_sfu(pid ${tf_sfu_pid})"

    # process exists, reload it
    kill -s SIGHUP ${tf_sfu_pid} 2>/dev/null
    ret=$?; if [[ 0 -ne $ret ]]; then failed_msg "reload tf_sfu failed ret=$ret"; return $ret; fi

    load_process_info
    if [[ 0 -ne $? ]]; then failed_msg "tf_sfu reload failed."; return $ret; fi

    ok_msg "tf_sfu reloaded"
    return 0
}

logrotate() {
    # not start, exit
    load_process_info
    if [[ 0 -ne $? ]]; then failed_msg "tf_sfu not start."; return 0; fi

    ok_msg "reopen log file of tf_sfu(pid ${tf_sfu_pid})..."
    kill -s SIGUSR1 ${tf_sfu_pid}

    ok_msg "log rotated"
    return 0
}

grace() {
    # not start, exit
    load_process_info
    if [[ 0 -ne $? ]]; then failed_msg "tf_sfu not start."; return 0; fi

    ok_msg "gracefully quit for tf_sfu(pid, ${tf_sfu_pid})..."
    kill -s SIGQUIT ${tf_sfu_pid}

    ok_msg "gracefully quit"
    return 0
}

usage() {
    echo "Usage: $0 {start|stop|status|restart|reload|rotate|grace}"
    echo "    reload    Apply log file by not restarting tf_sfu"
    echo "    rotate    For log rotate, to send SIGUSR1 to SRS to reopen the log file."
    echo "    grace    For gracefully quit, to send SIGQUIT to tf_sfu."
}

menu() {
    case "$1" in
        start)
            start
            ;;
        stop)
            stop
            ;;
        restart)
            stop
            start
            ;;
        status)
            status
            ;;
        reload)
            reload
            ;;
        rotate)
            logrotate
            ;;
        grace)
            grace
            ;;
        *)
            usage
            ;;
    esac
}

menu $1

code=$?
exit ${code}
