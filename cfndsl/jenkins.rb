# frozen_string_literal: true

require 'cfndsl'
require 'securerandom'

CloudFormation do
  params = {}
  external_parameters.each_pair do |key, val|
    key = key.to_sym
    params[key] = val
  end
  Description 'Jenkins Service'

  ECS_TaskDefinition(:jenkins) do
    ContainerDefinitions [{
      Image: 'gergnz/caddy-jenkins:lts',
      Memory: 500,
      Name: 'jenkins',
      MountPoints: [
        ContainerPath: '/var/jenkins_home',
        SourceVolume: 'efs'
      ],
      PortMappings: [{
        ContainerPort: 8090
      }, {
        ContainerPort: 50_000
      }],
      LogConfiguration: {
        LogDriver: :awslogs,
        Options: {
          'awslogs-region': Ref('AWS::Region'),
          'awslogs-group': FnJoin('-', [FnSelect('0', FnSplit('-', Ref('AWS::StackName'))), 'ecs']),
          'awslogs-stream-prefix': Ref('AWS::StackName')
        }
      }
    }]
    Volumes [{
      Name: 'efs',
      Host: {
        SourcePath: '/efs/shared/jenkins'
      }
    }]
  end

  ElasticLoadBalancingV2_TargetGroup(:target) do
    Name FnJoin('-', [Ref('AWS::StackName'), 'jenkins'])
    Port 80
    Protocol 'HTTP'
    VpcId FnImportValue(FnJoin('-', [FnSelect('0', FnSplit('-', Ref('AWS::StackName'))), 'vpc', 'VpcId']))
    Matcher(HttpCode: '200-299,400-499')
  end
  ElasticLoadBalancingV2_ListenerRule(:listenerrule) do
    ListenerArn FnImportValue(FnJoin('-', [FnSelect('0', FnSplit('-', Ref('AWS::StackName'))), 'ecs', 'httpslistener']))
    Priority 5
    Conditions [{
      Field: 'host-header',
      Values: ["jenkins.#{params[:prefix]}.b9f.io"]
    }]
    Actions [{
      TargetGroupArn: Ref(:target),
      Type: 'forward'
    }]
  end

  ECS_Service(:jenkinsservice) do
    DependsOn :listenerrule
    Cluster FnJoin('-', [FnSelect('0', FnSplit('-', Ref('AWS::StackName'))), 'ecs'])
    DesiredCount 1
    LoadBalancers [{
      ContainerName: 'jenkins',
      ContainerPort: 8090,
      TargetGroupArn: Ref(:target)
    }]
    TaskDefinition Ref(:jenkins)
    DeploymentConfiguration(
      MaximumPercent: 100,
      MinimumHealthyPercent: 0
    )
    Role FnJoin(':', ['arn:aws:iam:', Ref('AWS::AccountId'), 'role/aws-service-role/ecs.amazonaws.com/AWSServiceRoleForECS'])
  end

  Route53_RecordSet(:jenkinsrr) do
    AliasTarget(
      DNSName: FnImportValue(FnJoin('-', [FnSelect('0', FnSplit('-', Ref('AWS::StackName'))), 'ecs', 'alb', 'DNSName'])),
      HostedZoneId: FnImportValue(FnJoin('-', [FnSelect('0', FnSplit('-', Ref('AWS::StackName'))), 'ecs', 'alb', 'CanonicalHostedZoneID']))
    )
    Type 'A'
    HostedZoneName 'b9f.io.'
    Name "jenkins.#{params[:prefix]}.b9f.io"
  end

