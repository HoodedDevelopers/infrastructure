# frozen_string_literal: true

require 'cfndsl'
require 'securerandom'

AZS = %w[a b c].freeze
AZCOUNT = 3

CloudFormation do
  params = {}
  external_parameters.each_pair do |key, val|
    key = key.to_sym
    params[key] = val
  end
  Description 'VPC'

  Parameter(:cidr) do
    Type String
    AllowedPattern '((\d{1,3})\.){3}\d{1,3}/\d{1,2}'
    Description 'A CIDR block e.g. 10.0.0.0/16'
    ConstraintDescription 'must be a valid cidr ip block'
    MinLength 10
    MaxLength 19
  end

  Parameter(:natgw) do
    Type String
    AllowedValues %w[true false]
    Default 'false'
    Description 'To build NAT G/W or not to build'
    ConstraintDescription 'must be true or false'
  end

  Condition(
    :createnatgw, FnEquals(Ref(:natgw), 'true')
  )

  EC2_VPC(:vpc) do
    CidrBlock Ref(:cidr)
    EnableDnsSupport TRUE
    EnableDnsHostnames TRUE
    Tags [{ Key: :Name, Value: Ref('AWS::StackName') }]
  end
  EC2_VPCCidrBlock(:v6cidr) do
    AmazonProvidedIpv6CidrBlock TRUE
    VpcId Ref(:vpc)
  end
  Output(:VpcId) do
    Value Ref(:vpc)
    Export FnJoin('-', [Ref('AWS::StackName'), 'VpcId'])
  end

  EC2_InternetGateway(:igw) do
    Tags [{ Key: :Name, Value: Ref('AWS::StackName') }]
  end
  EC2_VPCGatewayAttachment(:igwatt) do
    InternetGatewayId Ref(:igw)
    VpcId Ref(:vpc)
  end
  EC2_EgressOnlyInternetGateway(:eigw) do
    VpcId Ref(:vpc)
  end

  EC2_RouteTable(:publicrt) do
    VpcId Ref(:vpc)
    Tags [{ Key: :Name, Value: FnJoin('-', [Ref('AWS::StackName'), :public]) }]
  end
  EC2_Route(:internetroute) do
    DestinationCidrBlock '0.0.0.0/0'
    RouteTableId Ref(:publicrt)
    GatewayId Ref(:igw)
  end
  EC2_Route(:v6internetroute) do
    DestinationIpv6CidrBlock '::/0'
    RouteTableId Ref(:publicrt)
    GatewayId Ref(:igw)
  end

  x = 0
  %w[public app db].each do |type|
    (0..AZCOUNT - 1).each do |i|
      EC2_Subnet("#{type}subnet#{i}") do
        VpcId Ref(:vpc)
        AvailabilityZone FnJoin('', [Ref('AWS::Region'), AZS[i]])
        CidrBlock FnSelect(i + x, FnCidr(Ref(:cidr), 256, 8))
        Ipv6CidrBlock FnSelect(i + x, FnCidr(FnSelect(0, FnGetAtt(:vpc, :Ipv6CidrBlocks)), 256, 64))
        Tags [{ Key: :Name, Value: FnJoin('-', [Ref('AWS::StackName'), "#{type}-#{AZS[i]}"]) }]
        DependsOn :v6cidr
      end
      Output("#{type}subnet#{AZS[i]}") do
        Value Ref("#{type}subnet#{i}")
        Export FnJoin('-', [Ref('AWS::StackName'), "#{type}subnet#{AZS[i]}"])
      end
      if type == 'public'
        EC2_SubnetRouteTableAssociation("publicrt#{i}") do
          RouteTableId Ref(:publicrt)
          SubnetId Ref("publicsubnet#{i}")
        end
        EC2_EIP("ip#{i}") do
          Domain :vpc
        end
        EC2_NatGateway("natgw#{i}") do
          Condition :createnatgw
          SubnetId Ref("publicsubnet#{i}")
          AllocationId FnGetAtt("ip#{i}", :AllocationId)
          Tags [{ Key: :Name, Value: FnJoin('-', [Ref('AWS::StackName'), AZS[i]]) }]
        end
        EC2_RouteTable("natrt#{i}") do
          VpcId Ref(:vpc)
          Tags [{ Key: :Name, Value: FnJoin('-', [Ref('AWS::StackName'), "natgw-#{AZS[i]}"]) }]
        end
        EC2_Route("natr#{i}") do
          Condition :createnatgw
          DestinationCidrBlock '0.0.0.0/0'
          RouteTableId Ref("natrt#{i}")
          NatGatewayId Ref("natgw#{i}")
        end
      else
        EC2_SubnetRouteTableAssociation("natrta#{type}#{i}") do
          RouteTableId Ref("natrt#{i}")
          SubnetId Ref("#{type}subnet#{i}")
        end
      end
    end
    x += AZCOUNT
  end
end
