# frozen_string_literal: true

require 'cfndsl'
require 'securerandom'

CloudFormation do
  params = {}
  external_parameters.each_pair do |key, val|
    key = key.to_sym
    params[key] = val
  end
  Description 'Nginx Service'

  ECS_TaskDefinition(:nginx) do
    ContainerDefinitions [{
      Image: 'nginx',
      Memory: 100,
      Name: 'nginx',
      MountPoints: [
        ContainerPath: '/usr/share/nginx/html',
        SourceVolume: 'efs'
      ],
      PortMappings: [{
        ContainerPort: 80
      }]
    }]
    Volumes [{
      Name: 'efs',
      Host: {
        SourcePath: '/efs/shared/nginx'
      }
    }]
  end

  ElasticLoadBalancingV2_TargetGroup(:target) do
    Name FnJoin('-', [Ref('AWS::StackName'), 'nginx'])
    Port 80
    Protocol 'HTTP'
    VpcId FnImportValue(FnJoin('-', [FnSelect('0', FnSplit('-', Ref('AWS::StackName'))), 'vpc', 'VpcId']))
  end
  ElasticLoadBalancingV2_ListenerRule(:listenerrule) do
    ListenerArn FnImportValue(FnJoin('-', [FnSelect('0', FnSplit('-', Ref('AWS::StackName'))), 'ecs', 'listener']))
    Priority 1
    Conditions [{
      Field: 'path-pattern',
      Values: ['/']
    }]
    Actions [{
      TargetGroupArn: Ref(:target),
      Type: 'forward'
    }]
  end

  ECS_Service(:nginxservice) do
    DependsOn :listenerrule
    Cluster FnJoin('-', [FnSelect('0', FnSplit('-', Ref('AWS::StackName'))), 'ecs'])
    DesiredCount 1
    LoadBalancers [{
      ContainerName: 'nginx',
      ContainerPort: 80,
      TargetGroupArn: Ref(:target)
    }]
    TaskDefinition Ref(:nginx)
    DeploymentConfiguration(
      MaximumPercent: 200,
      MinimumHealthyPercent: 0
    )
    Role FnJoin(':', ['arn:aws:iam:', Ref('AWS::AccountId'), 'role/aws-service-role/ecs.amazonaws.com/AWSServiceRoleForECS'])
  end
end
