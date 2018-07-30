# frozen_string_literal: true

require 'cfndsl'
require 'securerandom'

CloudFormation do
  params = {}
  external_parameters.each_pair do |key, val|
    key = key.to_sym
    params[key] = val
  end
  Description 'ECS Cluster'

  ECS_Cluster(:ecscluster) do
    ClusterName Ref('AWS::StackName')
  end

  Parameter(:ecsami) do
    Description 'ECS AMI ID'
    Type 'AWS::SSM::Parameter::Value<AWS::EC2::Image::Id>'
    Default '/aws/service/ecs/optimized-ami/amazon-linux/recommended/image_id'
  end

  assumestatement = { Statement: [
    {
      Action: [
        'sts:AssumeRole'
      ],
      Effect: 'Allow',
      Principal: {
        Service: [
          'ec2.amazonaws.com'
        ]
      }
    }
  ] }

  IAM_Role(:ecsrole) do
    AssumeRolePolicyDocument assumestatement
    Path '/'
    ManagedPolicyArns [
      'arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role',
      'arn:aws:iam::aws:policy/CloudWatchLogsFullAccess'
    ]
  end

  IAM_InstanceProfile(:asginstanceprofile) do
    Path '/'
    Role Ref(:ecsrole)
  end

  # Security group for connecting things
  EC2_SecurityGroup(:secgroup) do
    GroupDescription FnJoin('-', [Ref('AWS::StackName'), 'default'])
    VpcId FnImportValue(FnJoin('-', [FnSelect('0', FnSplit('-', Ref('AWS::StackName'))), 'vpc', 'VpcId']))
  end
  EC2_SecurityGroupEgress(:secgroupegress) do
    CidrIp '0.0.0.0/0'
    GroupId Ref(:secgroup)
    IpProtocol '-1'
    ToPort '-1'
    FromPort '-1'
  end
  EC2_SecurityGroupEgress(:v6secgroupegress) do
    CidrIpv6 '::/0'
    GroupId Ref(:secgroup)
    IpProtocol '-1'
    ToPort '-1'
    FromPort '-1'
  end
  EC2_SecurityGroupIngress(:secgroupingress) do
    SourceSecurityGroupId Ref(:secgroup)
    GroupId Ref(:secgroup)
    IpProtocol '-1'
    ToPort '-1'
    FromPort '-1'
  end
  Output(:secgroup) do
    Value Ref(:secgroup)
    Export FnJoin('-', [Ref('AWS::StackName'), 'secgroup', 'default'])
  end

  # Security group for http and https inbound
  EC2_SecurityGroup(:httphttps) do
    GroupDescription FnJoin('-', [Ref('AWS::StackName'), 'httpttps'])
    VpcId FnImportValue(FnJoin('-', [FnSelect('0', FnSplit('-', Ref('AWS::StackName'))), 'vpc', 'VpcId']))
  end
  EC2_SecurityGroupIngress(:http) do
    CidrIp '0.0.0.0/0'
    GroupId Ref(:httphttps)
    IpProtocol 'tcp'
    ToPort '80'
    FromPort '80'
  end
  EC2_SecurityGroupIngress(:https) do
    CidrIp '0.0.0.0/0'
    GroupId Ref(:httphttps)
    IpProtocol 'tcp'
    ToPort '443'
    FromPort '443'
  end
  EC2_SecurityGroupIngress(:v6http) do
    CidrIpv6 '::/0'
    GroupId Ref(:httphttps)
    IpProtocol 'tcp'
    ToPort '80'
    FromPort '80'
  end
  EC2_SecurityGroupIngress(:v6https) do
    CidrIpv6 '::/0'
    GroupId Ref(:httphttps)
    IpProtocol 'tcp'
    ToPort '443'
    FromPort '443'
  end

  ElasticLoadBalancingV2_LoadBalancer(:alb) do
    # rubocop:disable Lint/AmbiguousBlockAssociation
    Subnets %w[a b c].map { |az| FnImportValue(FnJoin('-', [FnSelect('0', FnSplit('-', Ref('AWS::StackName'))), 'vpc', "publicsubnet#{az}"])) }
    # rubocop:enable Lint/AmbiguousBlockAssociation
    IpAddressType :dualstack
    SecurityGroups [Ref(:secgroup), Ref(:httphttps)]
  end
  Output(:albDNSName) do
    Value FnGetAtt(:alb, 'DNSName')
    Export FnJoin('-', [Ref('AWS::StackName'), 'alb', 'DNSName'])
  end
  Output(:albCanonicalHostedZoneID) do
    Value FnGetAtt(:alb, 'CanonicalHostedZoneID')
    Export FnJoin('-', [Ref('AWS::StackName'), 'alb', 'CanonicalHostedZoneID'])
  end
  ElasticLoadBalancingV2_TargetGroup(:target) do
    Name FnJoin('-', [Ref('AWS::StackName'), 'default'])
    Port 80
    Protocol 'HTTP'
    VpcId FnImportValue(FnJoin('-', [FnSelect('0', FnSplit('-', Ref('AWS::StackName'))), 'vpc', 'VpcId']))
  end
  ElasticLoadBalancingV2_Listener(:listener) do
    Port 80
    Protocol 'HTTP'
    LoadBalancerArn Ref(:alb)
    DefaultActions [{
      Type: 'forward',
      TargetGroupArn: Ref(:target)
    }]
  end
  Output(:listener) do
    Value Ref(:listener)
    Export FnJoin('-', [Ref('AWS::StackName'), 'listener'])
  end
  ElasticLoadBalancingV2_Listener(:httpslistener) do
    Port 443
    Protocol 'HTTPS'
    Certificates [{ CertificateArn: params[:acm] }]
    LoadBalancerArn Ref(:alb)
    DefaultActions [{
      Type: 'forward',
      TargetGroupArn: Ref(:target)
    }]
  end
  Output(:httpslistener) do
    Value Ref(:httpslistener)
    Export FnJoin('-', [Ref('AWS::StackName'), 'httpslistener'])
  end

  EFS_FileSystem(:efs) do
    FileSystemTags [{ Key: :Name, Value: FnJoin('-', [Ref('AWS::StackName'), 'efs']) }]
  end

  %w[a b c].each do |az|
    EFS_MountTarget("mounttargeta#{az}") do
      FileSystemId Ref(:efs)
      SubnetId FnImportValue(FnJoin('-', [FnSelect('0', FnSplit('-', Ref('AWS::StackName'))), 'vpc', "appsubnet#{az}"]))
      SecurityGroups [Ref(:secgroup)]
    end
  end

  AutoScaling_LaunchConfiguration(:asglc) do
    KeyName FnSelect('0', FnSplit('-', Ref('AWS::StackName')))
    ImageId Ref(:ecsami)
    InstanceType 't2.small'
    SecurityGroups [Ref(:secgroup)]
    IamInstanceProfile Ref(:asginstanceprofile)
    UserData FnBase64(
      FnJoin('', ["#!/bin/bash\n",
                  'echo ECS_CLUSTER=', Ref(:ecscluster), " >> /etc/ecs/ecs.config\n",
                  "yum install -y nfs-utils\n",
                  "EC2_AVAIL_ZONE=`curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone`\n",
                  'EC2_REGION=', Ref('AWS::Region'), "\n",
                  'EFS_FILE_SYSTEM_ID=', Ref(:efs), "\n",
                  "DIR_SRC=$EC2_AVAIL_ZONE.$EFS_FILE_SYSTEM_ID.efs.$EC2_REGION.amazonaws.com\n",
                  "DIR_TGT=/efs/shared\n",
                  "mkdir -p $DIR_TGT\n",
                  "echo -e \"$DIR_SRC:/ \t\t $DIR_TGT \t\t nfs \t\t defaults \t\t 0 \t\t 0\" | tee -a /etc/fstab\n",
                  "mount -t nfs4 $DIR_SRC:/ $DIR_TGT\n",
                  "service docker stop\n",
                  "service docker start\n",
                  "echo FINISHED\n"])
    )
  end

  AutoScaling_AutoScalingGroup(:asg) do
    # rubocop:disable Lint/AmbiguousBlockAssociation
    VPCZoneIdentifier %w[a b c].map { |az| FnImportValue(FnJoin('-', [FnSelect('0', FnSplit('-', Ref('AWS::StackName'))), 'vpc', "appsubnet#{az}"])) }
    # rubocop:enable Lint/AmbiguousBlockAssociation
    LaunchConfigurationName Ref(:asglc)
    MinSize 0
    MaxSize 1
    DesiredCapacity 1
    Tags [{ Key: :Name, Value: FnJoin('-', [Ref('AWS::StackName'), 'asg']), PropagateAtLaunch: TRUE }]
  end

  Logs_LogGroup(:loggroup) do
    LogGroupName Ref('AWS::StackName')
    RetentionInDays 30
  end
end
