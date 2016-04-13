#!/usr/bin/perl

use strict;
use warnings;

package OESS::MPLS::Device::Juniper::MX;

use Template;
use Net::Netconf::Manager;
use Data::Dumper;

use constant FWDCTL_WAITING     => 2;
use constant FWDCTL_SUCCESS     => 1;
use constant FWDCTL_FAILURE     => 0;
use constant FWDCTL_UNKNOWN     => 3;

use GRNOC::Config;

use base "OESS::MPLS::Device";

sub new{
    my $class = shift;
    my %args = (
        @_
	);
    
    my $self = \%args;

    $self->{'logger'} = Log::Log4perl->get_logger('OESS.MPLS.Device.Juniper.MX.' . $self->{'host_info'}->{'mgmt_addr'});
    $self->{'logger'}->debug("MPLS Juniper Switch Created!");
    bless $self, $class;

    #TODO: make this automatically figure out the right REV
    $self->{'template_dir'} = "juniper/13.3R8/";

    $self->{'tt'} = Template->new(INCLUDE_PATH => "/usr/share/perl-OESS/share/mpls/templates/") or die "Unable to create Template Toolkit!";

    return $self;

}

sub disconnect{
    my $self = shift;

    $self->set_error("This device does not support disconnect");
    return;
}

sub get_system_information{
    my $self = shift;

    my $reply = $self->{'jnx'}->get_system_information();

    if($self->{'jnx'}->has_error){
        $self->{'logger'}->error("Error fetching interface information: " . $self->{'jnx'}->get_first_error());
        return;
    }

    my $system_info = $self->{'jnx'}->get_dom();
    my $xp = XML::LibXML::XPathContext->new( $system_info);
    $xp->registerNs('x',$system_info->documentElement->namespaceURI);
    warn $xp->find('/x:rpc-reply/x:system-information')->item(0)->toString();
    
    my $model = $xp->findvalue('/x:rpc-reply/x:system-information/x:hardware-model');
    my $version = $xp->findvalue('/x:rpc-reply/x:system-information/x:os-version');
    my $host_name = $xp->findvalue('/x:rpc-reply/x:system-information/x:host-name');
            
    return {model => $model, version => $version, vendor => 'Juniper', host_name => $host_name};
}

sub get_interfaces{
    my $self = shift;

    my $reply = $self->{'jnx'}->get_interface_information();

    if($self->{'jnx'}->has_error){
	$self->set_error($self->{'jnx'}->get_first_error());
        $self->{'logger'}->error("Error fetching interface information: " . $self->{'jnx'}->get_first_error());
        return;
    }

    my @interfaces;

    my $interfaces = $self->{'jnx'}->get_dom();
    my $xp = XML::LibXML::XPathContext->new( $interfaces);
    $xp->registerNs('x',$interfaces->documentElement->namespaceURI);
    $xp->registerNs('j',"http://xml.juniper.net/junos/13.3R1/junos-interface");
    my $ints = $xp->findnodes('/x:rpc-reply/j:interface-information/j:physical-interface');

    foreach my $int ($ints->get_nodelist){
	push(@interfaces, _process_interface($int));
    }

    return \@interfaces;
}

sub _process_interface{
    my $int = shift;
    
    my $obj = {};

    my $xp = XML::LibXML::XPathContext->new( $int );
    $xp->registerNs('j',"http://xml.juniper.net/junos/13.3R1/junos-interface");
    $obj->{'name'} = trim($xp->findvalue('./j:name'));
    $obj->{'admin_state'} = trim($xp->findvalue('./j:admin-status'));
    $obj->{'operational_state'} = trim($xp->findvalue('./j:oper-status'));
    $obj->{'description'} = trim($xp->findvalue('./j:description'));
    if(!defined($obj->{'description'}) || $obj->{'description'} eq ''){
	$obj->{'description'} = $obj->{'name'};
    } 

    return $obj;

}

sub remove_vlan{
    my $self = shift;
    my $ckt = shift;

    my $vars = {};
    $vars->{'circuit_name'} = $ckt->{'circuit_name'};
    $vars->{'interface'} = $ckt->{'interface'};
    $vars->{'vlan_tag'} = $ckt->{'vlan_tag'};
    $vars->{'primary_path'} = $ckt->{'primary_path'};
    $vars->{'backup_path'} = $ckt->{'backup_path'};

    $vars->{'switch'} = $self->{'node'}->{'name'};
    $vars->{'site_id'} = $self->{'node'}->{'node_id'};

    my $output;
    my $remove_template = $self->{'tt'}->process( $self->{'template_dir'} . "/ep_config_delete.xml", $vars, \$output) or warn $self->{'tt'}->error();

    return $self->_edit_config( config => $output );
}

sub add_vlan{
    my $self = shift;
    my $ckt = shift;
    
    my $vars = {};
    $vars->{'circuit_name'} = $ckt->{'circuit_name'};
    $vars->{'interface'} = $ckt->{'interface'};
    $vars->{'vlan_tag'} = $ckt->{'vlan_tag'};
    $vars->{'primary_path'} = $ckt->{'primary_path'};
    $vars->{'backup_path'} = $ckt->{'backup_path'};

    $vars->{'switch'} = $self->{'node'}->{'name'};
    $vars->{'site_id'} = $self->{'node'}->{'node_id'};
    
    my $output;
    my $remove_template = $self->{'tt'}->process( $self->{'template_dir'} . "/ep_config.xml", $vars, \$output) or warn $self->{'tt'}->error();
    
    return $self->_edit_config( config => $output );    
}

sub connect{
    my $self = shift;
    
    if($self->connected()){
	$self->{'logger'}->error("Already connected to device");
	return;
    }

    my $host_info = $self->{'host_info'};
    
    my $jnx = new Net::Netconf::Manager( 'access' => 'ssh',
					 'login' => $host_info->{'username'},
					 'password' => $host_info->{'password'},
					 'hostname' => $host_info->{'mgmt_addr'},
					 'port' => $host_info->{'port'} );
    if(!$jnx){
	$self->{'connected'} = 0;
    }else{
	$self->{'jnx'} = $jnx;
	$self->{'connected'} = 1;
    }
}

sub connected{
    my $self = shift;
    return $self->{'connected'};
}

sub _edit_config{
    my $self = shift;
    my %params = @_;

    if(!defined($params{'config'})){
	$self->{'logger'}->error("No Configuration specified!");
	return FWDCTL_FAILURE;
    }

    if(!$self->{'connected'}){
	$self->{'logger'}->error("Not currently connected to the switch");
	return FWDCTL_FAILURE;
    }
    
    my %queryargs = ( 'target' => 'candidate' );
    my $res = $self->{'jnx'}->lock_config(%queryargs);

    if($self->{'jnx'}->has_error){
	$self->{'logger'}->error("Error attempting to lock config: " . $self->{'jnx'}->get_first_error());
	return FWDCTL_FAILURE;
    }

    %queryargs = (
        'target' => 'candidate'
        );

    $queryargs{'config'} = $params{'config'};
    
    $res = $self->{'jnx'}->edit_config(%queryargs);

    if($self->{'jnx'}->has_error){
	$self->{'logger'}->error("Error attempting to modify config: " . $self->{'jnx'}->get_first_error());
	return FWDCTL_FAILURE;
    }

    $self->{'jnx'}->commit();
    if($self->{'jnx'}->has_error){
	$self->{'logger'}->error("Error attempting to commit the config: " . $self->{'jnx'}->get_first_error());
	return;
    }

    return FWDCTL_SUCCESS;
}

sub trim{
    my $s = shift; 
    $s =~ s/^\s+|\s+$//g;
    return $s
}

1;
