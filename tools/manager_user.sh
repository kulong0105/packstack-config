#!/bin/bash

#
# the format of config file looks be like:
#
# [platform-project]
# xiaoli
# xiaolin
#
# [finance-project]
# xiaoming
# xiaohua
#

usage()
{

	cat >&2 <<-EOF
Usage:
    $0 add -f config_file [-r]
    $0 add -u user_name [ -p project_name ] [-r]

    $0 del -f config_file
    $0 del -u user_name

Options:
    -f config_file:  specify the config file
    -u user_name":   specify the user name
    -p project_name: specify the project name, defaults to SkyData-Project
    -r :             use 'admin' role, defaults to '_member_' role

Arguments:
    add:  add user
    del:  remove user

Example:
    $0 add -f ./user_list
    $0 add -u allen -p platform_project -r admin

    $0 del -f ./user_list
    $0 del -u allen

EOF

	exit 1
}

log_info()
{
    echo
    echo "INFO: $*" >&2
}

log_warn()
{
    echo
    echo -e "\\x1b[1;33mWARNING: $*\\x1b[0m" >&2
}

log_error()
{
    echo
    echo -e "\\x1b[1;31mERROR: $* \\x1b[0m" >&2
}

check_command()
{
    local cmd="$1"

    command -v "$cmd" > /dev/null || {
        log_error "please install $cmd command"
        return 1
    }
}

create_keystonerc_file()
{
    local username="$1"
    local password="$2"
    local project_name="$3"
    local file_path="$4"

    cat > "$file_path" <<-EOF
unset OS_SERVICE_TOKEN
export OS_USERNAME=$username
export OS_PASSWORD=$password
export OS_AUTH_URL=http://10.0.2.21:5000/v3
export PS1='[\u@\h \W(keystonerc_yilong)]\$ '

export OS_PROJECT_NAME=$project_name
export OS_USER_DOMAIN_NAME=Default
export OS_PROJECT_DOMAIN_NAME=Default
export OS_IDENTITY_API_VERSION=3

EOF
}

check_keystone_auth()
{
    openstack project list &>/dev/null || {
        log_error "failed to get keystone authentication"
        return 1
    }
}

single_user_manager()
{
	local action=$1
	local user_name=$2
	local project_name=$3

	if [[ $action = "add" ]]; then

		if echo "$CURRENT_USER_LIST" | grep -q -x $user_name; then
			if [[ -z $PROJECT_USER_LIST ]]; then
				PROJECT_USER_LIST=$(openstack user list --project $project_name -f value | awk '{print $2}') || {
					log_error "faied to get user list from $project_name project"
					return 1
				}
			fi

			if echo "$PROJECT_USER_LIST" | grep -q -x "$user_name"; then
				log_warn "user \"$user_name\" have been exist in $project_name project, skip it!"
				return 0
			fi
		else
			openstack user create --domain default --project $project_name --password $DEFAULT_PASSWD $user_name >/dev/null
			CURRENT_USER_LIST="$CURRENT_USER_LIST
$user_name"
		fi

		openstack role add --project $project_name --user $user_name "$USER_ROLE" >/dev/null

		if [[ $? = 0 ]]; then
			log_info "succeed to create user \"$user_name\" in $project_name project"
		else
			log_error "failed to create user \"$user_name\" in $project_name project"
		fi
	else
		echo "$CURRENT_USER_LIST" | grep -q -x $user_name || {
			log_warn "user \"$user_name\" have been not exist, skip it!"
			return 0
		}

		if openstack user delete $user_name >/dev/null; then
			log_info "succeed to delete user \"$user_name\""
		else
			log_error "failed to delete user \"$user_name\""
		fi
	fi
}

multi_user_manager()
{
	local action=$1
	local config_file=$2

	local add_user_list
	local project_name

	local del_user_list

	[[ -s $config_file ]] || {
		log_error "cannot find config file: $config_file"
		return 1
	}

	if [[ $action = "add" ]]; then
		add_user_list=$(grep -v -e "^#" -e "^$" $config_file)
		for user in $add_user_list
		do
			if echo $user | grep -q "\["; then
				project_name=$(echo $user | tr -d "[" | tr -d "]")
				openstack project list -f value | awk '{print $2}' | grep -q -x "$project_name" || {
					openstack project create $project_name >/dev/null || return
				}
				PROJECT_USER_LIST=$(openstack user list --project $project_name -f value | awk '{print $2}') || {
					log_error "failed to get user list from $project_name project"
					return 1
				}
				continue
			fi
			single_user_manager "add" $user $project_name || return
		done
	else
		del_user_list=$(grep -v -e "^#" -e "^$" -e"\[" $config_file | sort -u)
		for user in $del_user_list
		do
			single_user_manager "del" $user || return
		done
	fi
}

cleanup()
{
    rm -f $temp_keystonerc_file
}

DEFAULT_PROJECT="SkyData-Project"
DEFAULT_PASSWD="123456"

ACTION=$1
[[ $ACTION = "add" || $ACTION = "del" ]] || {
	log_error "the action must be 'add' or 'del'"
	usage
}
shift

while getopts "f:u:p:rh" opt; do
    case $opt in
        f) CONFIG_FILE="$OPTARG" ; ;;
        u) USER_NAME="$OPTARG" ; ;;
        p) PROJECT_NAME="$OPTARG" ;;
        r) USER_ROLE="admin" ; ;;
        h | ?) usage ; ;;
    esac
done


[[ $CONFIG_FILE || $USER_NAME ]] || {
	log_error "must be use -u or -f option"
	usage
}

[[ $CONFIG_FILE && $USER_NAME ]] && {
	log_error "-u and -f cannot be used together"
	usage
}

if [[ $CONFIG_FILE ]]; then
	[[ -s $CONFIG_FILE ]] || {
		log_error "cannot file config file: $CONFIG_FILE"
		exit 1
	}
fi

[[ $USER_ROLE ]] || USER_ROLE="_member_"

[[ $PROJECT_NAME ]] || PROJECT_NAME=$DEFAULT_PROJECT

check_command "openstack" || exit

trap "cleanup; exit 1" INT EXIT
temp_keystonerc_file=$(mktemp)

log_info "preparing keystonerc file ..."
create_keystonerc_file "admin" "rootroot" "admin" $temp_keystonerc_file
source $temp_keystonerc_file

log_info "checking keystone authentication ..."
check_keystone_auth || exit


log_info "geting current user list ..."
CURRENT_USER_LIST=$(openstack user list -f value | awk '{print $2}') || {
	log_error "failed to get user list"
	exit 1
}

PROJECT_USER_LIST=
if openstack project list -f value | awk '{print $2}' | grep -q -w "$PROJECT_NAME"; then
	PROJECT_USER_LIST=$(openstack user list --project $PROJECT_NAME -f value | awk '{print $2}') || {
		log_error "failed to get user list from $PROJECT_NAME porject"
		exit 1
	}
else
	openstack project create $PROJECT_NAME >/dev/null || {
		log_error "failed to create project: $PROJECT_NAME"
		exit 1
	}
fi

log_info "add/delete user ..."

if [[ $CONFIG_FILE ]]; then
	multi_user_manager $ACTION $CONFIG_FILE
fi

if [[ $USER_NAME ]]; then
	single_user_manager $ACTION $USER_NAME $PROJECT_NAME
fi

