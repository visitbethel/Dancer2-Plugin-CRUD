package Dancer2::Plugin::DataModelMapper;

use Dancer2::Plugin;
use Dancer2::Logger::Console;
use Data::Dumper;
use Carp qw/croak carp/;


our $AUTHORITY = 'KAAN';
our $VERSION   = '0.01';
our $logger    = Dancer2::Logger::Console->new;

our $DEBUG_MAPPING = $ENV{'CRUD_MAP_TRACE'} || 0;

has mapping => (
                 is      => 'ro',
                 default => sub { return {} }
);


sub _register_map {
  my ( $self, $entity, $map ) = @_;
  if ( $map and $entity and not $self->mapping->{$entity} ) {
    $self->mapping->{$entity} = $map;
    print "...[CRUD] registering new model entity '$entity'.\n" if $DEBUG_MAPPING;
    
  }
  else {
    carp "Mapping for $entity already was registered!";
  }
}

sub _read_mapping {
  my ( $self, $entity ) = @_;
  return $self->mapping->{$entity};
  #return {};

}

register register_map => \&_register_map;
register bag      => \&_read_mapping;
register_plugin for_versions => [ 1, 2 ];

1;
