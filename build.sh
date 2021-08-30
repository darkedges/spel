#!/bin/bash -ex

if [ "$2" = "--debug" ]; then 
   build='build --debug'
else
   build='build'
fi

case $1 in
 aws)
    case $2 in
      7)
        packerBuildOnly="minimal-centos-7-hvm"
        ;;
      8)
        packerBuildOnly="minimal-centos-7-hvm"
        ;;
      *)
        echo "please pass one of '[7|8]'. Quiting"
        exit 1
        ;;
    esac
    ;;
 azure-vhd) 
    packerBuildOnly="minimal-centos-7-azure-vhd"
    ;;
 azure-image) 
    packerBuildOnly="minimal-centos-7-azure-image"
    ;;
 openstack) 
    packerBuildOnly="minimal-centos-7-openstack-image"
    ;;
 virtualbox)
    packerBuildOnly="virtualbox-iso"
    ;;
 *) echo "please pass one of '[aws|azure-vhd|azure-image|openstack|virtualbox]'. Quiting"
    exit 1
    ;;
esac

aws_ec2_instance_type=${instancetype:-t3.2xlarge}
buildid=${buildid:-1}
os=${os:-Centos79}
packerbin=${packerbin:-/usr/local/bin/packer}
packerjsonfile="spel/minimal-linux.json"
root_volume_size=${root_volume_size-20}
securitygroup_filter="Name=tag:Name,Values=darkedgessecuritygroup"
soeversion=${soeversion:-0.0.1}
source_ami_centos7_hvm=${source_ami_centos7_hvm:-ami-03d56f451ca110e99}
subnetname=${subnetname:-darkedgessubnet}
spel_identifier=${spel_identifier:-darkedges}
spel_version=${spel_version:-2021.08.1}
vpcname=${vpcname:-darkedgesvpc}
owner=${owner:-DarkEdges}
aws_ena_support=${aws_ena_support:-true}
aws_sriov_support=${aws_sriov_support:-true}

packervpcid=`aws ec2 describe-vpcs --filters "Name=tag:Name,Values=$vpcname" --query Vpcs[].VpcId --output text`
packersecuritygroupid=`aws ec2 describe-security-groups --filters Name=vpc-id,Values=$packervpcid $securitygroup_filter --query SecurityGroups[0].GroupId --output text`
packersubnetid=`aws ec2 describe-subnets --filters Name=vpc-id,Values=$packervpcid --filters "Name=tag:Name,Values=$subnetname" --query Subnets[].SubnetId --output text`
az=`aws ec2 describe-subnets --filters Name=vpc-id,Values=$packervpcid --filters "Name=tag:Name,Values=$subnetname" --query Subnets[].AvailabilityZone --output text`
aws_region=${az%?}
ami_description="darkedges-$os-$soeversion-$buildid"

echo "Build..."
$packerbin $build \
  -var "ami_description=$ami_description" \
  -var "aws_ec2_instance_type=$aws_ec2_instance_type" \
  -var "aws_region=$aws_region" \
  -var "aws_security_group_id=$packersecuritygroupid" \
  -var "owner=$owner" \
  -var "root_volume_size=$root_volume_size" \
  -var "source_ami_centos7_hvm=$source_ami_centos7_hvm" \
  -var "spel_identifier=$spel_identifier" \
  -var "spel_version=$spel_version" \
  -var "subnet_id=$packersubnetid" \
  -var "aws_ena_support=$aws_ena_support" \
  -var "aws_sriov_support=$aws_sriov_support" \
  -only "$packerBuildOnly" \
  $packerjsonfile

echo "Now wait until we can obtain the just built ami..."
until aws ec2 describe-images --filters "Name=description,Values=*$ami_description*" --output text | grep "ami-"; do
  sleep 10
done

ami=`aws ec2 describe-images --filters "Name=description,Values=*$ami_description*" --query Images[*].ImageId  --output text`

#share AMI with AWS account sharewithawsaccount
if [ ! $sharewithawsaccount = "none" ]; then
  aws ec2 modify-image-attribute --image-id $ami --launch-permission "{\"Add\":[{\"UserId\":\"$sharewithawsaccount\"}]}"
fi