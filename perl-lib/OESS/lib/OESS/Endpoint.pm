#!/usr/bin/perl

use strict;
use warnings;

package OESS::Endpoint;

use OESS::DB;
use OESS::DB::Endpoint;
use OESS::Interface;
use OESS::Entity;
use OESS::Node;
use OESS::Peer;
use OESS::Entity;
use Data::Dumper;


=head1 OESS::Endpoint

An C<Endpoint> represents an edge connection of a circuit or vrf.

=cut

=head2 new

B<Example 0:>

    my $ep = new OESS::Endpoint(
        db => $db,
        circuit_ep_id => 100,
        vrf_ep_id     => 100
    }

    # or

    my $ep = new OESS::Endpoint(
        db => $db,
        model => {
            entity              => 'mx960-1',
            entity_id           => 3,
            node                => 'test.grnoc.iu.edu',
            node_id             => 2,
            interface           => 'xe-7/0/2',
            interface_id        => 57,
            unit                => 6,
            tag                 => 6,
            inner_tag           => undef,
            bandwidth           => 0,
            cloud_account_id    => undef,
            cloud_connection_id => undef,
            mtu                 => 9000,
            operational_state   => 'up'
        }
    )

B<Example 1:>

    my $json = {
        inner_tag           => undef,      # Inner VLAN tag (qnq only)
        tag                 => 1234,       # Outer VLAN tag
        cloud_account_id    => '',         # AWS account or GCP pairing key
        cloud_connection_id => '',         # Probably shouldn't exist as an arg
        entity              => 'us-east1', # Interfaces to select from
        bandwidth           => 100,        # Acts as an interface selector and validator
        workgroup_id        => 10,         # Acts as an interface selector and validator
        mtu                 => 9000,
        unit                => 345,
        peerings            => [ {...} ]
    };
    my $endpoint = OESS::Endpoint->new(db => $db, type => 'vrf', model => $json);

B<Example 2:>

    my $json = {
        inner_tag           => undef,      # Inner VLAN tag (qnq only)
        tag                 => 1234,       # Outer VLAN tag
        cloud_account_id    => '',         # AWS account or GCP pairing key
        cloud_connection_id => '',         # Probably shouldn't exist as an arg
        node                => 'switch.1', # Name of node to select
        interface           => 'xe-7/0/1', # Name of interface to select
        bandwidth           => 100,        # Acts as an interface validator
        workgroup_id        => 10,         # Acts as an interface validator
        mtu                 => 9000,
        unit                => 345,
        peerings            => [ {...} ]
    };
    my $endpoint = OESS::Endpoint->new(db => $db, type => 'vrf', model => $json);

=cut
sub new{
    my $that  = shift;
    my $class = ref($that) || $that;

    my $logger = Log::Log4perl->get_logger("OESS.Endpoint");

    my %args = (
        details => undef,
        vrf_id => undef,
        db => undef,
        @_
    );

    my $self = \%args;
    
    bless $self, $class;

    $self->{'logger'} = $logger;

    if(!defined($self->{'db'})){
        $self->{'logger'}->error("No Database Object specified");
        return;
    }

    if ((defined($self->circuit_id()) && $self->circuit_id() != -1) ||
        (defined($self->vrf_endpoint_id()) && $self->vrf_endpoint_id() != -1)){
        $self->_fetch_from_db();
    }else{
        $self->_build_from_model();
    }

    return $self;
}

=head2 _build_from_model

=cut
sub _build_from_model{
    my $self = shift;

    $self->{'inner_tag'} = $self->{'model'}->{'inner_tag'};
    $self->{'tag'} = $self->{'model'}->{'tag'};
    $self->{'bandwidth'} = $self->{'model'}->{'bandwidth'};
    $self->{cloud_account_id} = $self->{model}->{cloud_account_id};
    $self->{cloud_connection_id} = $self->{model}->{cloud_connection_id};
    $self->{mtu} = $self->{model}->{mtu};

    if (defined $self->{'model'}->{'interface'}) {
        $self->{'interface'} = OESS::Interface->new(db => $self->{'db'}, name => $self->{'model'}->{'interface'}, node => $self->{'model'}->{'node'});
        $self->{'entity'} = OESS::Entity->new(db => $self->{'db'}, interface_id => $self->{'interface'}->{'interface_id'}, vlan => $self->{'tag'});
    } else {
        $self->{'entity'} = OESS::Entity->new(db => $self->{'db'}, name => $self->{'model'}->{'entity'});

        # There are a few ways to select an Entity's interface.

        # The default selection method is to find the first interface
        # that has supports C<bandwidth> and has C<tag> available.

        # As there is only one interface per AWS Entity there is no
        # special selection method.

        # Interface selection for a GCP Entity is based purely on the
        # user provided GCP pairing key.

        # Interface selection for an Azure Entity is somewhat
        # irrelevent. Each interface of the Azure port pair is
        # configured similarly with the only difference between the
        # two being the peer addresses assigned to each.

        my $err = undef;
        foreach my $intf (@{$self->{entity}->interfaces()}) {
            my $valid_bandwidth = $intf->is_bandwidth_valid(bandwidth => $self->{model}->{bandwidth});
            if (!$valid_bandwidth) {
                $err = "The choosen bandwidth for this Endpoint is invalid.";
            }

            my $valid_vlan = 0;
            if (defined $self->{model}->{workgroup_id}) {
                $valid_vlan = $intf->vlan_valid(
                    vlan         => $self->{model}->{tag},
                    workgroup_id => $self->{model}->{workgroup_id}
                );
                if (!$valid_vlan) {
                    $err = "The selected workgroup cannot use vlan $self->{model}->{tag} on $self->{model}->{entity}.";
                }
            } else {
                warn "Endpoint model is missing workgroup_id. Skipping vlan validation.";
                $valid_vlan = 1;
            }

            if ($valid_vlan && $valid_bandwidth) {
                $self->{interface} = $intf;
                last;
            }
        }

        if (!defined $self->{interface}) {
            return $err;
        }
    }

    if ($self->{type} eq 'vrf' || defined $self->{'vrf_endpoint_id'}) {
        $self->{'peers'} = [];

        foreach my $peer (@{$self->{'model'}->{'peerings'}}) {
            push @{$self->{'peers'}}, OESS::Peer->new(db => $self->{'db'}, model => $peer, vrf_ep_peer_id => -1);
        }
    } else {
        $self->{circuit_id} = $self->{model}->{circuit_id};
        $self->{circuit_ep_id} = $self->{model}->{circuit_edge_id} || $self->{model}->{circuit_ep_id};
        $self->{start_epoch} = $self->{model}->{start_epoch};
    }

    $self->{'unit'} = $self->{'model'}->{'unit'};
}

=head2 to_hash

=cut
sub to_hash{
    my $self = shift;
    my $obj;

    $obj->{'interface'} = $self->interface()->to_hash();
    $obj->{'node'} = $self->interface()->node()->to_hash();
    $obj->{'inner_tag'} = $self->inner_tag();
    $obj->{'tag'} = $self->tag();
    $obj->{'bandwidth'} = $self->bandwidth();
    $obj->{cloud_account_id} = $self->cloud_account_id();
    $obj->{cloud_connection_id} = $self->cloud_connection_id();
    if(defined($self->entity())){
        $obj->{'entity'} = $self->entity->to_hash();
    }
    if (defined $self->{'vrf_endpoint_id'}) {

        my @peers;
        foreach my $peer (@{$self->{'peers'}}){
            push(@peers, $peer->to_hash());
        }

        $obj->{'peers'} = \@peers;
        $obj->{'vrf_id'} = $self->vrf_id();
        $obj->{'vrf_endpoint_id'} = $self->vrf_endpoint_id();
        $obj->{'mtu'} = $self->mtu();
        $obj->{'type'} = 'vrf';
    }else{
        $obj->{'circuit_id'} = $self->circuit_id();
        $obj->{'circuit_ep_id'} = $self->circuit_ep_id();
        $obj->{'start_epoch'} = $self->start_epoch();
        $obj->{'type'} = 'circuit';
    }

    $obj->{'unit'} = $self->{'unit'};
    return $obj;

}

=head2 from_hash

=cut
sub from_hash{
    my $self = shift;
    my $hash = shift;

    $self->{'bandwidth'} = $hash->{'bandwidth'};
    $self->{'interface'} = $hash->{'interface'};

    $self->{cloud_account_id} = $hash->{cloud_account_id};
    $self->{cloud_connection_id} = $hash->{cloud_connection_id};

    if ($self->{'type'} eq 'vrf' || !defined $hash->{'circuit_ep_id'}) {
        $self->{'peers'} = $hash->{'peers'};
        $self->{'vrf_id'} = $hash->{'vrf_id'};
        $self->{'mtu'} = $hash->{'mtu'};
    } else {
        $self->{'circuit_id'} = $hash->{'circuit_id'};
        $self->{'circuit_ep_id'} = $hash->{'circuit_ep_id'};
        $self->{start_epoch} = $hash->{start_epoch};
    }

    $self->{'inner_tag'} = $hash->{'inner_tag'};
    $self->{'tag'} = $hash->{'tag'};
    $self->{'bandwidth'} = $hash->{'bandwidth'};

    $self->{'unit'} = $hash->{'unit'};

    $self->{'entity'} = OESS::Entity->new( db => $self->{'db'}, interface_id => $self->{'interface'}->{'interface_id'}, vlan => $self->{'tag'});
}

=head2 _fetch_from_db

=cut
sub _fetch_from_db{
    my $self = shift;

    my $db = $self->{'db'};
    my $hash;

    if($self->{'type'} eq 'circuit'){
        my ($data, $err) = OESS::DB::Endpoint::fetch_all(
            circuit_id => $self->{circuit_id},
            interface_id => $self->{interface_id}
        );
        if (!defined $err) {
            $hash = $data->[0];
        }

        # Do a little moving around to make the hash compatible with from_hash
        $hash->{'interface'} = {'interface_id' => $hash->{'interface_id'}}

    }else{

        $hash = OESS::DB::VRF::fetch_endpoint(db => $db, vrf_endpoint_id => $self->{'vrf_endpoint_id'});
    }
    $self->from_hash($hash);

}

=head2 get_endpoints_on_interface

=cut
sub get_endpoints_on_interface{
    my %args = @_;
    my $db = $args{'db'};
    my $interface_id = $args{'interface_id'};
    my $state = $args{'state'} || 'active';
    my $type = $args{'type'} || 'all';
    my @results; 

    # Gather all VRF endpoints
    if ($type eq 'all' || $type eq 'vrf') {
        my $endpoints = OESS::DB::VRF::fetch_endpoints_on_interface(
                                db => $db,
                                interface_id => $interface_id,
                                state => $state);
        foreach my $endpoint (@$endpoints){
            push(@results, OESS::Endpoint->new(
                                db => $db,
                                type => 'vrf',
                                vrf_endpoint_id => $endpoint->{'vrf_ep_id'}));
        }
    }
  
    # Gather all Circuit endpoints
    if ($type eq 'all' || $type eq 'circuit') {
        my $endpoints = OESS::DB::Circuit::fetch_endpoints_on_interface(
                                db => $db,
                                interface_id => $interface_id); 
        foreach my $endpoint (@$endpoints){
            push(@results, OESS::Endpoint->new(
                                db => $db,
                                type => 'circuit',
                                model => $endpoint));
        }
    }
    return \@results;
}

=head2 cloud_account_id

=cut
sub cloud_account_id {
    my $self = shift;
    my $value = shift;
    if (defined $value) {
        $self->{cloud_account_id} = $value;
    }
    return $self->{cloud_account_id};
}

=head2 cloud_connection_id

=cut
sub cloud_connection_id {
    my $self = shift;
    my $value = shift;
    if (defined $value) {
        $self->{cloud_connection_id} = $value;
    }
    return $self->{cloud_connection_id};
}

=head2 interface

=cut
sub interface{
    my $self = shift;
    my $interface = shift;

    if(defined($interface)){
        $self->{'interface'} = $interface;
    }

    return $self->{'interface'};
}

=head2 node

=cut
sub node{
    my $self = shift;
    return $self->{'interface'}->node();
}

=head2 node_id

=cut
sub node_id {
    my $self = shift;
    return $self->{'interface'}->node->node_id;
}

=head2 type

=cut
sub type{
    my $self = shift;
    $self->{'type'};
}

=head2 mtu

=cut
sub mtu {
    my $self = shift;
    my $mtu = shift;

    if (defined $mtu) {
        $self->{'mtu'} = $mtu;
    }
    return $self->{'mtu'};
}

=head2 peers

=cut
sub peers{
    my $self = shift;
    my $peers = shift;

    if(defined($peers)){
        $self->{'peers'} = $peers;
    }

    if(!defined($self->{'peers'})){
        return [];
    }

    return $self->{'peers'};
}

=head2 inner_tag

=cut
sub inner_tag{
    my $self = shift;
    my $inner_tag = shift;

    if (defined $inner_tag) {
        $self->{'inner_tag'} = $inner_tag;
    }
    return $self->{'inner_tag'};
}

=head2 tag

=cut
sub tag{
    my $self = shift;
    my $tag = shift;

    if (defined $tag) {
        $self->{'tag'} = $tag;
    }
    return $self->{'tag'};
}

=head2 bandwidth

=cut
sub bandwidth{
    my $self = shift;
    return $self->{'bandwidth'};
}

=head2 vrf_endpoint_id

=cut
sub vrf_endpoint_id{
    my $self = shift;
    return $self->{'vrf_endpoint_id'};
}

=head2 vrf_id

=cut
sub vrf_id{
    my $self = shift;
    return $self->{'vrf_id'};
}

=head2 circuit_id

=cut
sub circuit_id{
    my $self = shift;
    return $self->{'circuit_id'};
}

=head2 start_epoch

=cut
sub start_epoch{
    my $self = shift;
    my $start_epoch = shift;
    if(defined($start_epoch)) {
        $self->{start_epoch} = $start_epoch;
    }
    return $self->{start_epoch};
}

=head2 circuit_ep_id

=cut
sub circuit_ep_id{
    my $self = shift;
    return $self->{'circuit_ep_id'};
}

=head2 entity

=cut
sub entity{
    my $self = shift;
    return $self->{'entity'};
}

=head2 unit

=cut
sub unit{
    my $self = shift;
    my $unit = shift;

    if(defined($unit)){
        $self->{'unit'} = $unit;
    }

    return $self->{'unit'};
}

=head2 workgroup_id

=cut
sub workgroup_id {
    my $self = shift;
    my $workgroup_id = shift;
    if (defined $workgroup_id) {
        $self->{'workgroup_id'} = $workgroup_id;
    }
    return $self->{'workgroup_id'};
}

=head2 decom

=cut
sub decom{
    my $self = shift;

    my $res;
    if($self->type() eq 'vrf'){
        foreach my $peer (@{$self->peers()}){
            $peer->decom();
        }

        $res = OESS::DB::VRF::decom_endpoint(db => $self->{'db'}, vrf_endpoint_id => $self->vrf_endpoint_id());

    }else{

        $res = OESS::DB::Circuit::decom_endpoint(db => $self->{'db'}, circuit_endpoint_id => $self->circuit_ep_id());

    }

    return $res;

}

=head2 update_db_vrf

=cut
sub update_db_vrf{
    my $self = shift;
    my $endpoint = $self->to_hash();
    
    my $result = OESS::DB::Endpoint::remove_vrf_peers(db => $self->{db},
                        endpoint => $endpoint);
    if(!defined($result)){
        $self->{db}->rollback();
        return $self->{db}->{error};
    }
    
    $result = OESS::DB::Endpoint::add_vrf_peers(db => $self->{db},
                        endpoint => $endpoint);
    if(!defined($result)){
        $self->{db}->rollback();
        return $self->{db}->{error};
    }

    $result = OESS::DB::Endpoint::update_vrf(db => $self->{db},
                        endpoint => $endpoint);    
    if(!defined($result)){
        $self->{db}->rollback();
        return $self->{db}->{error};
    }
    return undef;
}

=head2 update_db_circuit

=cut
sub update_db_circuit{
    my $self = shift;
    my $endpoint = $self->to_hash();

    my $result = OESS::DB::Endpoint::remove_circuit_edge_membership(
                        db       => $self->{db},
                        endpoint => $endpoint);
    if(!defined($result)){
        return $self->{db}->{error};
    }

    $result = OESS::DB::Endpoint::update_circuit_edge_membership(
                        db       => $self->{db},
                        endpoint => $endpoint);
    if(!defined($result)){
        return $self->{db}->{error};
    }
    return;
}

=head2 update_db

=cut 
sub update_db {
    my $self = shift;
    my $error = undef;

    if ($self->type() eq 'vrf' || defined $self->{vrf_endpoint_id}) {
        $error = $self->update_db_vrf();
    } elsif ($self->type() eq 'circuit' || defined $self->{circuit_ep_id}) {
        $error = $self->update_db_circuit();
    } else {
        $error = 'Unknown Endpoint type specified.';
    }

    return $error;
}

=head2 move_endpoints

=cut
sub move_endpoints{
    my %args = @_;
    my $db = $args{db};
    my $orig_interface_id  = $args{orig_interface_id};
    my $new_interface_id   = $args{new_interface_id};
    my $type   = $args{type} || 'all';
    my %used_vlans;
    my %used_units;
  
    # Gather occupied vlans on the new interface 
    my $new_endpoints = get_endpoints_on_interface(
                        db => $db,
                        interface_id => $new_interface_id);
    foreach my $endpoint (@$new_endpoints) {
        # Note tag pairs for QnQ, and just the outer tag for non-QnQ
        if(defined($endpoint->inner_tag())) {
            $used_vlans{$endpoint->tag()}{$endpoint->inner_tag()} = 1;
        }else{
            $used_vlans{$endpoint->tag()} = 1;
        }
        $used_units{$endpoint->unit()} = 1;
    }

    # Gather the endpoints we want to attempt to move
    my $orig_endpoints = get_endpoints_on_interface(
                            db => $db,
                            interface_id => $orig_interface_id,
                            type => $type);
    foreach my $endpoint (@$orig_endpoints) {
        # Check if our tag pair conflicts with the new interface
        if(($used_vlans{$endpoint->tag()} == 1) ||
           ($used_vlans{$endpoint->tag()}{$endpoint->inner_tag()} == 1)){
            next;
        } 

        # If QnQ, make sure no unit conflicts, or alternatively just generate a new one
        my $new_unit_number = $endpoint->unit();
        if($endpoint->inner_tag() != undef && $used_units{$endpoint->unit()}) {
            $new_unit_number = $endpoint->interface()->find_available_unit(
                    interface_id => $new_interface_id,
                    tag          => $endpoint->tag(),
                    inner_tag    => $endpoint->inner_tag());
        }

        # Update the interface_id (and unit number if needed)
        # TODO: Update end_epoch for circuits in circuit_edge_interface_membership
        $endpoint->unit($new_unit_number);
        $endpoint->{interface} = OESS::Interface->new(
                db => $db,
                interface_id => $new_interface_id);
        $endpoint->update_db();
    }
    return 1;
}

=head2 create

    $db->start_transaction;
    my ($id, $err) = $ep->create(
        circuit_id   => 100, # Optional
        vrf_id       => 100  # Optional
        workgroup_id => 100
    );
    if (defined $err) {
        $db->rollback;
        warn $err;
    }

create saves this Endpoint along with its Peers to the database. This
method B<must> be wrapped in a transaction and B<shall> only be used
to create a new Endpoint.

=cut
sub create {
    my $self = shift;
    my $args = {
        circuit_id   => undef,
        vrf_id       => undef,
        workgroup_id => undef,
        @_
    };

    if (!defined $self->{db}) {
        $self->{'logger'}->error("Couldn't create Endpoint: DB handle is missing.");
        return (undef, "Couldn't create Endpoint: DB handle is missing.");
    }

    return (undef, 'Required argument `workgroup_id` is missing.') if !defined $args->{workgroup_id};

    my $ok = $self->interface()->vlan_valid(
        workgroup_id => $args->{workgroup_id},
        vlan => $self->tag
    );
    if (!$ok) {
        my $name = $self->interface()->name;
        my $tag = $self->tag;
        $self->{'logger'}->error("Couldn't create Endpoint: Outer tag $tag cannot be used by $args->{workgroup_id} on $name.");
        return (undef, "Couldn't create Endpoint: Outer tag $tag cannot be used by $args->{workgroup_id} on $name.");
    }

    my $unit = OESS::DB::Endpoint::find_available_unit(
        db => $self->{db},
        interface_id => $self->interface->{'interface_id'},
        tag => $self->tag,
        inner_tag => $self->inner_tag
    );
    if (!defined $unit) {
        $self->{'logger'}->error("Couldn't create Endpoint: Couldn't find an available Unit.");
        return (undef, "Couldn't create Endpoint: Couldn't find an available Unit.");
    }

    if (defined $args->{circuit_id}) {
        my $ep_data = $self->to_hash;
        $ep_data->{circuit_id} = $args->{circuit_id};
        $ep_data->{unit} = $unit;

        my $circuit_ep_id = OESS::DB::Endpoint::add_circuit_edge_membership(
            db => $self->{db},
            endpoint => $ep_data
        );
        if (!defined $circuit_ep_id) {
            $self->{'logger'}->error("Couldn't create Endpoint: " . $self->{db}->get_error);
            return (undef, "Couldn't create Endpoint: " . $self->{db}->get_error);
        }

        $self->{circuit_ep_id} = $circuit_ep_id;
        return ($circuit_ep_id, undef);

    } elsif (defined $args->{vrf_id}) {
        # TODO add vrf endpoint
        $self->{'logger'}->error("Couldn't create Endpoint: VRF Endpoint creation not supported here.");
        return (undef, "Couldn't create Endpoint: VRF Endpoint creation not supported here.");

    } else {
        $self->{'logger'}->error("Couldn't create Endpoint: No associated Circuit or VRF identifier specified.");
        return (undef, "Couldn't create Endpoint: No associated Circuit or VRF identifier specified.");
    }

}

=head2 remove

    my $error = $endpoint->remove;
    if (defined $error) {
        warn $error;
    }

remove deletes this endpoint from the
circuit_edge_interface_membership or vrf_ep table depending on if it's
a Circuit or VRF Endpoint. This method should be wrapped in a
transaction.

=cut
sub remove {
    my $self = shift;
    my $args = { @_ };

    if (!defined $self->{db}) {
        $self->{logger}->error("Couldn't remove Endpoint: DB handle is missing.");
        return "Couldn't remove Endpoint: DB handle is missing.";
    }

    my $endpoint = $self->to_hash;

    if ($self->type eq 'vrf' || defined $self->{vrf_endpoint_id}) {
        my $result = OESS::DB::Endpoint::remove_vrf_peers(
            db => $self->{db},
            endpoint => $endpoint
        );
        if (!defined $result) {
            return $self->{db}->{error};
        }

        my $error = OESS::DB::Endpoint::remove_vrf_ep(
            db => $self->{db},
            vrf_ep_id => $endpoint->{vrf_ep_id}
        );
        return $error if (defined $error);
    }
    elsif ($self->type eq 'circuit' || defined $self->{circuit_ep_id}) {
        my $result = OESS::DB::Endpoint::remove_circuit_edge_membership(
            db       => $self->{db},
            endpoint => $endpoint
        );
        if (!defined $result) {
            return $self->{db}->{error};
        }
    }
    else {
        return 'Unknown Endpoint type specified.';
    }

    return;
}

1;
