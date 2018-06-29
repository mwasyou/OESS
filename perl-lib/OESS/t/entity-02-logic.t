#!/usr/bin/perl -T

use strict;

use FindBin;
my $path;

BEGIN {
    if($FindBin::Bin =~ /(.*)/){
        $path = $1;
    }
}

use lib "$path";
use OESS::Database;
use OESS::Entity;
use OESSDatabaseTester;

use Test::More tests => 18;
use Test::Deep;
use Data::Dumper;

my $db = OESS::Database->new( config => OESSDatabaseTester::getConfigFilePath() );

my $ent1 = OESS::Entity->new( entity_id => 2, db => $db );
ok(defined($db) && defined($ent1), 'Sanity check: can instantiate OESS::Database and OESS::Entity objects');

ok($ent1->entity_id() == 2,       'Entity 1 returns correct entity_id');
ok($ent1->name() eq 'Connectors', 'Entity 1 returns correct name');
ok($ent1->description eq 'Those that are included in this classification', 'Entity 1 returns correct description');
ok(!defined($ent1->url()),        'Entity 1 returns correct (null) URL');
ok(!defined($ent1->logo_url()),   'Entity 1 returns correct (null) logo URL');
cmp_deeply($ent1->users(), [],    'Entity 1 returns correct (empty) users list');
cmp_deeply(
    $ent1->interfaces(),
    [],
    'Entity 1 returns correct (empty) interfaces list'
);
cmp_deeply(
    $ent1->parents(),
    bag(
        {
            entity_id   => 1,
            name        => 'root',
            description => 'The top of the hierarchy blah blah blah',
            logo_url    => undef,
            url         => 'ftp://example.net/pub/',
        },
    ),
    'Entity 1 returns correct list of parents'
);
cmp_deeply(
    $ent1->children(),
    bag(
        {
            entity_id   => 7,
            name        => 'Big State TeraPOP',
            description => 'The R&E networking hub for Big State',
            logo_url    => 'https://terapop.example.net/favicon.ico',
            url         => 'https://terapop.example.net/',
        },
        {
            entity_id   => 8,
            name        => 'Small State MilliPOP',
            description => undef,
            logo_url    => undef,
            url         => 'https://smst.millipop.net/',
        },
    ),
    'Entity 1 returns correct list of children'
);



my $ent2 = OESS::Entity->new( name => 'B University-Metropolis', db => $db );

ok($ent2->entity_id() == 14,                       'Entity 2 returns correct entity_id');
ok($ent2->name() eq 'B University-Metropolis',     'Entity 2 returns correct name');
ok($ent2->url() eq 'https://b-metro.example.edu/', 'Entity 2 returns correct URL');
ok(!defined($ent2->logo_url()),                    'Entity 2 returns correct logo URL');
cmp_deeply(
    [ map {ref $_} @{$ent2->users()} ],
    [ 'OESS::User', 'OESS::User' ],
    'Entity 2: users() returns two User objects'
);
cmp_deeply(
    [ map {$_->user_id()} @{$ent2->users()} ],
    bag(
        121,
        881,
    ),
    'Entity 2: users() returns proper users'
);
warn Dumper($ent2->interfaces());
cmp_deeply(
    [ map {ref $_} @{$ent2->interfaces()} ],
    [ 'OESS::Interface' ],
    'Entity 2: interfaces() returns one Interface object'
);
cmp_deeply(
    [ map {$_->interface_id()} @{$ent2->interfaces()} ],
    bag(
        35961,
    ),
    'Entity 2: interfaces() returns correct interfaces'
);
