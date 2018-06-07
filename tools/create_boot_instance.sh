#!/bin/bash

usage()
{
    cat >&2 <<EOF

Usage:
    $0 <-o instance_name> [-i image_name] [-s volume_size] [-k keypair_name] [-f flavor_name] [-n network_name] [-H hypervisor_name] [-u username] [-p password] [-P project_name] create
    $0 <-o instance_name> <-I boot_volume_id> [-k keypair_name] [-f flavor_name] [-n network_name] [-H server_placement] [-u username] [-p password] [-P project_name] boot

Command:
    create: create a new instance using related flavor, image, etc
    boot:   boot a new instance from a exist volume

Options:
    -o instance_name:       instance name
    -I boot_volume_id:      from volume boot instance's id

    -i image_name:          boot instance's image name, default value is "skydata-cpu"
    -s volume_size:         volume size, unit is GB, default value is "20"
    -k keypair_name:        SSH public key's keypair name, defalut value is "yilong"
    -f flavor_name:         boot instance's flavor name, default value is "skydata-medium"
    -n network_name:        internal network name, defalut value is "ci-network-internal"
    -H hypervisor_name:     location where instance run, use Openstack Scheduler by default
    -u username:            username in OpenStack/User, default value is "yilong.ren"
    -p password:            password in OpenStack/User, default value is "rootroot"
    -P project_name:        project name, defalut value is "CI-Team"

Examples:
    $0 -o ci_team_test01 create
    $0 -o ci_tema_test02 -i skydata-cpu -s 30 -k yilong -f skydata-medium -n ci-network-internal -H 22-server.localdomain -u yilong.ren -p rootroot -P CI-Team create

    $0 -o ci_team_test03 -I 28fb88e2-c8f7-4a18-bea9-3efefa26c00d boot
    $0 -o ci_team_test04 -I 28fb88e2-c8f7-4a18-bea9-3efefa26c00d -k yilong -f skydata-medium -n ci-network-internal -H 22-server.localdomain -u yilong.ren -p rootroot -P CI-Team boot
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

check_volume_bootable()
{
    local volume_id="$1"
    local project_name="$2"

    cinder list | grep -q -w $volume_id  || {
        log_error "cannot find volume id: $volume_id under $project_name project"
        return 1
    }

	cinder list | grep -w $volume_id | grep -q -w "true" || {
        log_error "volume: $volume_id is not bootable"
        return 1
    }
}

check_image_name()
{
	local image_name="$1"

	openstack image list | grep -q -w "$image_name" || {
		log_error "cannot find image_name: $image_name"
		return 1
	}
}

check_keypair_name()
{
	local keypair_name="$1"

	openstack keypair list | grep -q -w "$keypair_name" || {
		log_error "cannot find keypair_name: $keypair_name"
		return 1
	}
}

check_flavor_name()
{
	local flavor_name="$1"

	openstack flavor list | grep -q -w "$flavor_name" || {
		log_error "cannot find flavor_name: $flavor_name"
		return 1
	}
}

check_network_name()
{
	local network_name="$1"

	openstack network list | grep -q -w "$network_name" || {
		log_error "cannot find network_name: $network_name"
		return 1
	}
}

check_hypervisor_name()
{
	local hypervisor_name="$1"

	nova service-list | grep nova-compute | awk '{print $6}' | grep -q -x "$hypervisor_name" || {
		log_error "cannot find hypervisor_name: $hypervisor_name"
		return 1
	}
}

check_instance_name()
{
	local instance_name="$1"

	[[ $(openstack server list --format csv --name "$instance_name" | wc -l) -eq 1 ]] || {
		log_error "$instance_name has been used by others"
		return 1
	}
}

create_instance()
{
    local instance_name="$1"
    local image_name="$2"
    local volume_size="$3"
    local keypair_name="$4"
    local flavor_name="$5"
    local network_name="$6"

    local updated_volume_name="${instance_name}_os"
    local instance_volume_name

	local image_id=$(openstack image list --format value | grep -w "$image_name" | awk '{print $1}')

	local options="--poll"
	[[ $hypervisor_name ]] && options="$options --availability-zone nova:${hypervisor_name}"

    nova boot --block-device source=image,id=$image_id,dest=volume,size=$volume_size,shutdown=preserve,bootindex=0 \
		--key-name $keypair_name --flavor $flavor_name --nic net-name=$network_name $options $instance_name || {
		log_error "failed to create $instance_name instance"
		return 1
	}

    instance_volume_name=$(openstack server show --format shell "$instance_name" | grep "volumes_attached" | awk -F"'" '{print $2}')
    openstack volume set --name "$updated_volume_name" "$instance_volume_name" || {
        log_error "failed update volume's from $instance_volume_name to $updated_volume_name"
        return 1
    }
}

boot_instance()
{
	local instance_name="$1"
	local boot_volume_id="$2"
	local keypair_name="$3"
	local flavor_name="$4"
	local network_name="$5"

	local options="--poll"
	[[ $hypervisor_name ]] && options="$options --availability-zone nova:${hypervisor_name}"

	nova boot --boot-volume $boot_volume_id --key-name $keypair_name --flavor $flavor_name \
	--nic net-name=$network_name $options  $instance_name || {
		log_error "failed to create $instance_name instance"
		return 1
	}
}

cleanup()
{
	rm -f $temp_keystonerc_file
}

while getopts "o:I:i:s:k:f:n:H:u:p:P:h" option; do
    case "$option" in
        o)  instance_name="$OPTARG";    ;;
        I)  boot_volume_id="$OPTARG";  ;;
        i)  image_name="$OPTARG";   ;;
        s)  volume_size="$OPTARG";  ;;
        k)  keypair_name="$OPTARG"; ;;
        f)  flavor_name="$OPTARG";  ;;
        n)  network_name="$OPTARG"; ;;
        H)  hypervisor_name="$OPTARG"; ;;
        u)  username="$OPTARG"; ;;
        p)  password="$OPTARG"; ;;
        P)  project_name="$OPTARG";  ;;
        h | ?)  usage;  ;;
    esac
done

shift $((OPTIND-1))
action="$1"

[[ "$action" ]] || {
    log_error "the sub-command create or boot is required"
    usage
}

if [[ "$action" = "create" ]]; then
    [[ "$instance_name" ]] || {
        log_error "-o option is required for 'create' command"
        usage
    }
elif [[ "$action" = "boot" ]]; then
    [[ "$instance_name" && "$boot_volume_id" ]] || {
        log_error "-o and -I options are required for 'boot' command"
        usage
    }
else
    log_error "the sub-command only support 'boot' and 'create'"
    usage
fi

[[ "$image_name" ]] || image_name="skydata-cpu"
[[ "$volume_size" ]] || volume_size="20"
[[ "$keypair_name" ]] || keypair_name="yilong"
[[ "$flavor_name" ]] || flavor_name="skydata-medium"
[[ "$network_name" ]] || network_name="ci-network-internal"
[[ "$hypervisor_name" ]] || hypervisor_name=
[[ "$username" ]] || username="yilong.ren"
[[ "$password" ]] || password="rootroot"
[[ "$project_name" ]] || project_name="CI-Team"

check_command "openstack" || exit
check_command "nova" || exit

trap "cleanup; exit 1" INT EXIT
temp_keystonerc_file=$(mktemp)

log_info "preparing keystonerc file for $project_name ..."
create_keystonerc_file $username $password $project_name $temp_keystonerc_file
source $temp_keystonerc_file

log_info "checking keystone authentication ..."
check_keystone_auth || exit


if [[ "$action" = "create" ]]; then
	log_info "checking image name ..."
	check_image_name "$image_name" || exit

	log_info "checking keypair name ..."
	check_keypair_name "$keypair_name" || exit

	log_info "checking network name ..."
	check_network_name "$network_name" || exit

	if [[ $hypervisor_name ]]; then
		log_info "checking hypervisor name ..."
		check_hypervisor_name "$hypervisor_name" || exit
	fi

	log_info "checking instance name ..."
	check_instance_name "$instance_name" || exit

	log_info "creating instance $instance_name ..."
	create_instance "$instance_name" "$image_name" "$volume_size" "$keypair_name" "$flavor_name" "$network_name" || exit

    log_info "successfully creating instance: $instance_name
	image_name:       $image_name
	volume_size:      $volume_size
	keypair_name:     $keypair_name
	flavor_name:      $flavor_name
	network_name:     $network_name
	hypervisor_name:  $hypervisor_name
	username:         $username
	password:         $password
	project_name      $project_name
	"
else
	log_info "checking volume_bootable ..."
	check_volume_bootable "$boot_volume_id" "$project_name" || exit

	log_info "checking keypair name ..."
	check_keypair_name "$keypair_name" || exit

	log_info "checking network name ..."
	check_network_name "$network_name" || exit

	if [[ $hypervisor_name ]]; then
		log_info "checking hypervisor name ..."
		check_hypervisor_name "$hypervisor_name" || exit
	fi

	log_info "checking instance name ..."
	check_instance_name "$instance_name" || exit

	log_info "booting instance $instance_name ..."
	boot_instance "$instance_name" "$boot_volume_id" "$keypair_name" "$flavor_name" "$network_name" || exit

    log_info "successfully booting instance: $instance_name
	boot_volume_id:   $boot_volume_id
	keypair_name:     $keypair_name
	flavor_name:      $flavor_name
	network_name:     $network_name
	hypervisor_name:  $hypervisor_name
	username:         $username
	password:         $password
	project_name      $project_name
	"
fi
