package Dancer2::Plugin::MapperUtils;

use Data::Dumper;

use Moose::Role;
use Carp qw/carp/;
use Sub::Exporter -setup => {
  exports => [
    qw(map_row
    map_fields
    )
  ]
};

our $DEBUG_RESULTSET = 0;
our $DEBUG_MAPPING   = $ENV{'CRUD_MAP_TRACE'} || 0;

=head
  making up the return array with results which can be a mixin
  of array / hash values based on the mapping defenintion.
  
  $field_defs = [ 'json_field' => ['table1_ref', 'table2_ref' => [ 'id' ,'desc' ]] ]
  would return json value of record
    json_field : [
      'table2_ref' : { 'id' : value, 'desc' : value }
    ]

   table wise it would fetch the following columns
   json_field : [
      'table2_ref' : { 'id' : table1_ref->table2_ref->id, 'desc' : table1_ref->table2_ref->desc }
    ]

=cut

sub map_field {
  my ( $k, $method, $base ) = @_;
  my $value = undef;

  if ( ref($method) eq '' ) {
    &logf( "      : %s->%s traverse\n", 'base', $method );
    $base = $base->$method if $base;
    return $base;
  }
  elsif ( ref($method) eq 'HASH' ) {

    # if there is a base find its path values.
    if ($base) {

      # array ref, multiple values in one
      my %bag = ();
      foreach my $hashkeys ( keys %{$method} ) {
        &logf( "HASH : %s->%s baging ref(%s)\n",
               $method, $hashkeys, ref( $base->$hashkeys ) );
        $bag{ $method->{$hashkeys} } = $base->$hashkeys;
      }
      $value = \%bag;
    }
    else {
      $value = undef;
    }
  }
  else {

    # if there is a base find its path values.
    if ($base) {

      # array ref, multiple values in one
      my %bag = ();
      foreach my $hashkeys ( @{$method} ) {
        $bag{$hashkeys} = $base->$hashkeys;
        &logf( "ARRAY: %s->%s baging ref(%s)\n",
               $method, $hashkeys, ref( $base->$hashkeys ) );
      }

      #&logf(Dumper( \%bag );
      $value = \%bag;
    }
    else {
      $value = undef;
    }
  }
}

sub map_fields {
  my ( $field_defs, @rs ) = @_;
  
  unless ($field_defs) {
  	carp "missing mapping for mapping fields.";
  	return;
  }
  
  &logf( "MAPPING:" . Dumper($field_defs) );
  my @result = ();
  foreach my $row (@rs) {
    if (!blessed($row)) {
      next;
    }
    push @result, &map_row( $field_defs, $row );
  }
  &logf( Dumper( \@result ) );
  return \@result;
}

sub map_row {
  my ( $field_defs, $row ) = @_;
  my $rec = {};
  while ( my ( $k, $v ) = each %$field_defs ) {

    &logf( "\t%s => %s\n", $k, ref($v) );
    if ( ref($v) eq 'ARRAY' ) {
      &logf("\nARRAY: \n");
      my $base  = $row;
      my $value = undef;
      foreach my $method (@$v) {
        $base = &map_field( $k, $method, $base );
      }
      $rec->{$k} = $base;
    }
    elsif ( ref($v) eq 'HASH' ) {
      &logf("\nHASH : \n");

      my $base = $row;
      $rec->{$k} = &map_field( $k, $v, $base );
    }
    else {
      &logf("\nVAR  : \n");
      &logf( "\t : %s->%s baging ref(%s) value=%s\n",
             $v, $k,
             ref( $row->$k ),
             $row->$k ? $row->$k : 'NA' );
      $rec->{$v} = $row->$k;
    }
  }
  &logf( "RECORD:", Dumper($rec) );
  return $rec;
}

sub logf {
  printf @_ if $DEBUG_MAPPING;
}

1;
