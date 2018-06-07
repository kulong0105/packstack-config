#!/bin/bash

usage()
{
    cat >&2 <<EOF

Usage:
    $0 [-u username] [-p password] [-P project_name] <-i instance_id>

Options:

    -u username:            username in OpenStack/User, default value is "yilong.ren"
    -p password:            password in OpenStack/User, default value is "rootroot"
    -P project_name:        project name, defalut value is "CI-Team"

    -i instance_id:         instance's id
EOF

	exit 1
}

log_info()
{
    echo
    echo -e "\e[1;33mINFO: $* \e[0m" >&2
}

log_error()
{
    echo
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


check_instance_id()
{
	local instance_id="$1"

	nova list | grep -q -w "$instance_id" || {
		log_error "cannot find instance id: $instance_id"
		return 1
	}
}

migrate_instance()
{
	local instance_id="$1"

	openstack server migrate $instance_id || {
		log_error "failed to migrate instance"
		return 1
	}
}

resize_confirm_instance()
{
	local instance_id="$1"
	local vm_status

	vm_status=$(openstack server show $instance_id | grep status | awk '{print $4}')

	local loop=1
	while [[ "$vm_status" != "VERIFY_RESIZE" ]]
	do
		if [[ $loop -gt 20 ]]; then
			log_error "instance's status is not VERIFY_RESIZE"
			return 1
		fi

		echo "waiting instance's status to be VERIFY_RESIZE for $((loop * 6)) seconds"
		vm_status=$(openstack server show $instance_id | grep status | awk '{print $4}')
		loop=$((loop + 1))
		sleep 6
	done

	nova resize-confirm $instance_id || {
		log_error "failed to resize-confirm $instance_id"
		return 1
	}
}

show_instance()
{
	local instance_id="$1"

	openstack server show $instance_id
}

cleanup()
{
	rm -f $temp_keystonerc_file
}

check_command "openstack" || exit
check_command "nova" || exit

while getopts "u:p:P:i:h" option; do
    case "$option" in
        u)  username="$OPTARG"; ;;
        p)  password="$OPTARG"; ;;
        P)  project_name="$OPTARG";  ;;
        i)  instance_id="$OPTARG";   ;;
        h | ?)  usage;  ;;
    esac
done

[[ $instance_id ]]  || {
	log_error "-i option is required"
	usage
}

[[ "$username" ]] || username="yilong.ren"
[[ "$password" ]] || password="rootroot"
[[ "$project_name" ]] || project_name="CI-Team"

trap "cleanup; exit 1" INT EXIT
temp_keystonerc_file=$(mktemp)

log_info "preparing keystonerc file for $project_name ..."
create_keystonerc_file $username $password $project_name $temp_keystonerc_file
source $temp_keystonerc_file

log_info "checking keystone authentication ..."
check_keystone_auth || exit

log_info "checking instance id ..."
check_instance_id "$instance_id" || exit

log_info "migrating instance to alternate host..."
migrate_instance "$instance_id" || exit

log_info "resize-confirm instance ..."
resize_confirm_instance "$instance_id" || exit

log_info "succeed to instance migrated and resized"
show_instance "$instance_id"

