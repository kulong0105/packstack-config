#!/bin/bash

usage()
{
    cat >&2 <<-EOF

Usage:
    $0 <-i volume_id> <-t volume_status> [-u username] [-p password] [-P project_name]

Option:
    -i volume_id:       specify volume ID, format looks like faadd197-e907-4ca4-8080-1a888f74c6ba
    -t volume_status:   specify volume status, only support "available" and  "deleted" value
    -u username:        username in OpenStack/User, default value is yilong.ren
    -p password:        password in OpenStack/User, default value is rootroot
    -P project_name:    project name, Defalut value is CI-Team

Example:
    $0 -i faadd197-e907-4ca4-8080-1a888f74c6ba -t available -P DB-Team
    $0 -i faadd197-e907-4ca4-8080-1a888f74c6ba -t deleted

EOF
    exit 1
}

log_info()
{
    echo -e "\e[1;33mINFO: $* \e[0m" >&2
}

log_error()
{
    echo -e "\e[1;31mERROR: $* \e[0m" >&2
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

check_volume_available()
{
	local volume_id="$1"
	local project_name="$2"

	cinder list | grep -w -q $volume_id  || {
		log_error "cannot find volume id: $volume_id under $project_name project"
		return 1
	}
}

change_volume_status()
{
    local volume_id="$1"
    local volume_status="$2"
    local update_volume="UPDATE volumes SET status = $volume_status WHERE id = \"$volume_id\" "

    mysql -u root -P 3306 -h localhost --database cinder -e "$update_volume" || {
        log_error "cannot update $volume_id to $volume_status status"
        exit 1
    }

    if [[ "$volume_status" = "deleted" ]]; then
        cinder force-delete "$volume_id" || {
            log_error "cannot delete $volume_id volume using cinder"
            return 1
        }
    fi
}

cleanup()
{
	rm -f $temp_keystonerc_file
}

while getopts "i:t:u:p:P:h" option; do
    case "$option" in
        i) volume_id="$OPTARG";    ;;
        t) volume_status="$OPTARG";    ;;
        u) username="$OPTARG"; ;;
        p) password="$OPTARG"; ;;
        P) project_name="$OPTARG"; ;;
        h | ?)  usage;  ;;
    esac
done

[[ "$volume_id" && "$volume_status" ]] ||  {
	log_error "-i and -t options are required."
	usage
}

[[ "$volume_status" = "available" || "$volume_status" = "deleted" ]] || {
	log_error "only support 'available' and 'deleted' value for -t option"
	usage
}

[[ $username ]] || username="yilong.ren"
[[ $password ]] || password="rootroot"
[[ $project_name ]] || project_name="CI-Team"

check_command "openstack" || exit
check_command "mysql" || exit
check_command "cinder" || exit

trap "cleanup; exit 1" INT EXIT
temp_keystonerc_file=$(mktemp)

log_info "preparing keystonerc file for $project_name ..."
create_keystonerc_file $username $password $project_name $temp_keystonerc_file
source $temp_keystonerc_file

log_info "checking keystone authentication ..."
check_keystone_auth || exit

log_info "checking volume id available ..."
check_volume_available "$volume_id" "$project_name" || exit

log_info "changing volume status ..."
change_volume_status "$volume_id" "$volume_status" || exit

log_info "succeed to update volume $volume_id to $volume_status status"
