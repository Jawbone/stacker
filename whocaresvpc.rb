## Example of a VPC using the ruby DSL

description "Create a VPC or something"

parameter :cidr do
    description "The CIDR block for the VPC."
    type :string
    allowed_pattern "(\\d{1,3})\\.(\\d{1,3})\\.(\\d{1,3})\\.(\\d{1,3})/(\\d{1,2})"
    min_length 9
    max_length 18
    default "10.0.0.0/16"
end

resource :vpc do
    type "AWS::EC2::VPC"
    properties do
        CidrBlock ref(:cidr)
        EnableDnsHostnames true
        EnableDnsSupport true
        Tags [{"Key" => "Application", "Value" => stack_id } ]
    end
end
output :vpc_id do
    description "Id for the vpc."
    value ref(:vpc)
end
resource :internet_gateway do
    type "AWS::EC2::InternetGateway"
    properties do
        Tags [{"Key" => "Application", "Value" => stack_id }]
    end
end
output :internet_gateway_id do
    description "Id for the internet gateway."
    value ref(:internet_gateway)
end
resource :gateway_attachment do
    type "AWS::EC2::VPCGatewayAttachment"
    properties do
        VpcId ref(:vpc)
        InternetGatewayId ref(:internet_gateway)
    end
end
resource :public_route_table do
    type "AWS::EC2::RouteTable"
    properties do
        VpcId ref(:vpc)
        Tags [{"Key" => "Application", "Value" => stack_id }]
    end
end
output :public_route_table do
    description "Route table going to the public internet."
    value ref(:public_route_table)
end
resource :public_route do
    type "AWS::EC2::Route"
    depends_on :gateway_attachment
    properties do
        RouteTableId ref(:public_route_table)
        DestinationCidrBlock "0.0.0.0/0"
        GatewayId ref(:internet_gateway)
    end
end
