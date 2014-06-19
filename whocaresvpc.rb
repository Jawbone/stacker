## Example of a VPC using the ruby DSL

description "Create a VPC or something"

parameter :cidr, :type => :string do
    Description "The CIDR block for the VPC."
    AllowedPattern "(\\d{1,3})\\.(\\d{1,3})\\.(\\d{1,3})\\.(\\d{1,3})/(\\d{1,2})"
    MinLength 9
    MaxLength 18
    Default "10.0.0.0/16"
end

resource :vpc, :type => 'AWS::EC2::VPC' do
    properties do
        CidrBlock ref(:cidr)
        EnableDnsHostnames true
        EnableDnsSupport true
        Tags [{"Key" => "Application", "Value" => stack_id } ]
    end
    output :vpcId, :description => "Id for the VPC!"
end
resource :internetGateway do
    type "AWS::EC2::InternetGateway"
    properties do
        Tags [{"Key" => "Application", "Value" => stack_id }]
    end
end
## The other way prolly works too.. Maybe
output :internetGateway do
    Description "Id for the internet gateway."
    Value ref(:internetGateway)
end
resource :gatewayAttachment do
    type "AWS::EC2::VPCGatewayAttachment"
    properties do
        VpcId ref(:vpc)
        InternetGatewayId ref(:internetGateway)
    end
end
resource :publicRouteTable, :type => 'AWS::EC2::RouteTable' do
    properties do
        VpcId ref(:vpc)
        Tags [{"Key" => "Application", "Value" => stack_id }]
    end
    output :publicRouteTable
end

resource :publicRoute do
    type "AWS::EC2::Route"
    DependsOn :gatewayAttachment
    properties do
        RouteTableId ref(:publicRouteTable)
        DestinationCidrBlock "0.0.0.0/0"
        GatewayId ref(:internetGateway)
    end
    output :publicRoute do
        Description "The route the the public internet gateway."
    end
end
{
    'us-east-1a' => ['10.0.1.0/24', '10.0.10.0/24'],
    'us-east-1d' => ['10.0.2.0/24' ,'10.0.11.0/24'],
    'us-east-1e' => ['10.0.3.0/24', '10.0.12.0/24']
}.each do |az,subnets|
    az_name = az[-2..az.length].to_sym
    subnets.each do |subnet|
        subnet_name = "subnet#{az_name.capitalize}#{subnet.split('.')[2]}".to_sym
        resource subnet_name, :type => 'AWS::EC2::Subnet' do
            properties do
                VpcId ref(:vpc)
                CidrBlock subnet
                AvailabilityZone az
                Tags [{"Key" => "Application", "Value" => stack_id }]
            end
            output subnet_name, :description => "Subnet #{subnet} in az #{az}"
        end
        resource "#{subnet_name}RouteTableAssoc" do
            Type 'AWS::EC2::SubnetRouteTableAssociation'
            properties do
                SubnetId ref(subnet_name)
                RouteTableId ref(:publicRouteTable)
            end
        end
    end

end
