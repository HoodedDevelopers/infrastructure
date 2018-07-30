# frozen_string_literal: true

require 'cfndsl'
require 'securerandom'

CloudFormation do
  params = {}
  external_parameters.each_pair do |key, val|
    key = key.to_sym
    params[key] = val
  end
  Description 'Bootstrap Task'

  ECS_TaskDefinition(:bootstrap) do
    ContainerDefinitions [{
      Image: 'gergnz/bootstrap:0.1',
      Memory: 100,
      Name: 'bootstrap',
      MountPoints: [
        ContainerPath: '/efs/shared',
        SourceVolume: 'efs'
      ]
    }]
    Volumes [{
      Name: 'efs',
      Host: {
        SourcePath: '/efs/shared'
      }
    }]
  end

  ECS_Service(:bootstrapservice) do
    Cluster FnJoin('-', [FnSelect('0', FnSplit('-', Ref('AWS::StackName'))), 'ecs'])
    DesiredCount 1
    TaskDefinition Ref(:bootstrap)
    DeploymentConfiguration(
      MaximumPercent: 100,
      MinimumHealthyPercent: 0
    )
  end
end
