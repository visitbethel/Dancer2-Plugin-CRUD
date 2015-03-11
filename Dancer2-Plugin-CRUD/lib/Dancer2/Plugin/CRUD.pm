package Dancer2::Plugin::CRUD;

use Dancer2::Plugin;
use Dancer2::Logger::Console;
use Data::Dumper;
use Dancer2::Plugin::MapperUtils qw(map_row);
use Carp;
use Scalar::Util qw(blessed);
use Try::Tiny;
with 'Dancer2::Plugin::MapperUtils';
our $AUTHORITY         = 'KAAN';
our $VERSION           = '0.01';
our $DEFAULT_PAGE_SIZE = 5;
our $DEBUG_MAPPING     = 1;
our $logger            = Dancer2::Logger::Console->new;

has new_record_mapping => ( is => 'ro', default => sub { return {} } );

=head
  ___ NEW RECORD ___
=cut

sub register_rec {
  my ( $self, $entity, $coderef ) = @_;
  if ( $coderef and $entity and not $self->new_record_mapping->{lc $entity} ) {
    $self->new_record_mapping->{lc $entity} = $coderef;
    print "...[CRUD] registering new record entity '$entity'.\n";
  }
  else {
    carp "Mapping for $entity already was registered!";
  }
}

sub _new_record {
  my ( $self, $entity ) = @_;
  return $self->new_record_mapping->{$entity} ? $self->new_record_mapping->{$entity}->() : ();
}


=head
  ___ CREATE ___
=cut
sub create_rec {
  my ( $self, $store, $table, $mapping, $record_json ) = @_;
  my $class  = $store->resultset($table);
  my ($pk)   = $class->result_source->primary_columns();
  my %fields = %{$mapping};

  %fields = reverse %fields;

  print Dumper($self->_new_record(lc $table));
  my %new_record = $self->_new_record(lc $table);

  &logf("\nNEW EMPTY RECORD: (", lc $table, ")", Dumper( \%new_record ));
  foreach my $dbfield ( keys %fields ) {
    my $method = $fields{$dbfield};
    my $strref = sprintf "%s", $dbfield;

    #$strref =~ s/HASH//g;
    &logf( $strref, "<---", $record_json, "\n" );
    if ( ref($method) eq '' and $record_json->{$strref} ) {
      $new_record{$method} = $record_json->{$strref};
    }
  }
  &logf( "\n-->%s, NEWRECORD: %s, NEWJSON: %s", Dumper( \%fields ), Dumper( \%new_record ), Dumper($record_json) );

  my $return;
  my $transactionref = sub {
    my $_record = $store->resultset($table)->create( \%new_record );

    #&logf( Dumper($_record));

    # apply complex changes first.
    if (blessed($_record) and $_record->can('complex_update_or_create') ) {
      $_record->complex_update_or_create( $record_json, $mapping );
    }
    $self->process_rec( $_record, $mapping, $record_json );
    return $_record;
  };

  my $record;
  try {
    $record = $store->txn_do($transactionref);
  }
  catch {
    my $error = shift;
    &logf($error);
    DBIx::Class::Exception->throw('[[Record already exists!]]');
  };
  return &map_row( $mapping, $record );

}

=head
  ___ READ ___
=cut

sub read_rec {
  my ( $self, $store, $table, $mapping, $id ) = @_;
  my $record = $store->resultset($table)->find($id);
  unless ($record) {
    DBIx::Class::Exception->throw('[[Record does not exist!]]');
  }
  my $mp = &map_row( $mapping, $record );
  &logf( "READING[%d]: %s", $id, Dumper($mp) );
  return $mp;
}


=head
  ___ UPDATE ___
=cut

sub update_rec {
  my ( $self, $store, $table, $mapping, $record_json ) = @_;
  my $class = $store->resultset($table);
  my ($pk) = $class->result_source->primary_columns();

  my $transactionref = sub {
    my $_record = $class->find( { $pk => $record_json->{'id'} } );

    &logf("record to update: ", Dumper($record_json));
    # apply complex changes first.
    if (blessed($_record) and $_record->can('complex_update_or_create') ) {
    	
      $_record->complex_update_or_create( $record_json, $mapping );
    }

    $self->process_rec( $_record, $mapping, $record_json );
    return $_record;
  };

  my $record;
  try {
    $record = $store->txn_do($transactionref);
  }
  catch {
    DBIx::Class::Exception->throw( '[[Record could not be updated!]]: Reason:' . $_ );
  };
  return &map_row( $mapping, $record );
}

=head
  ___ PROCESS ___
=cut

sub process_rec {
  my ( $self, $record, $mapping, $record_json ) = @_;
  &logf( "PROCESS RECORD: %s", Dumper($record_json) );
  my %fields = %{$mapping};

  %fields = reverse %fields;
  &logf( "--> %s\n", Dumper( \%fields, $record_json ) );
  foreach my $dbfield ( keys %fields ) {
    &logf( "-->[mapping] = %s\n", $dbfield );
    my $method = $fields{$dbfield};
    &logf( "-->[key----] = %s\n", keys %$record_json );
    if ( defined $record_json->{$dbfield} ) {
      if ( $record->can($method) ) {
        &logf("...1 set $method = $record_json->{$dbfield}\n");
        $record->$method( $record_json->{$dbfield} ) if ref($method) eq '';
      }
      else {
        &logf( "MAPPING ERROR %s method not found on $record", $method );
      }
    }
    else {

      if ( $dbfield =~ /^ARRAY/ ) {
        my $property = $method;
        printf "...2 %s \n", $property;
        next unless $record_json->{$property};
        printf "...4 %s = %s [ %s ]\n", $property, $record_json->{$property}, $mapping->{$property};

        # find the first element relationship links and take that as the method for the resultset.
        $method = $mapping->{$property}->[0];
        print "...4b\n";
        printf "%s -> method=%s->map=%s, [%s]\n", $property, $method, $dbfield, ref($record);    # if $DEBUG_MAPPING;
        printf "...4c -> record = blessed ? %s\n", blessed($record);
        if (blessed($record) and $record->can($method) ) {
        	if (ref $record_json->{$property} eq '') {
		        $record->$method( $record_json->{$property} );
        	}
        }
        else {
        	print "$record->$method( $record_json->{$property}  ) FAILED \n";
        }
        printf "...5 end of \n";
      }
      else {
        printf "...6\n";
        printf "MAPPING ERROR %s ( %s ) = %s\n", $dbfield, $record_json->{$dbfield} ? $record_json->{$dbfield} : '???', $method;
      }
    }
  }
  return $record->update();
}

sub logf {
  printf @_ if $DEBUG_MAPPING;
}

=head
  ___ DELETE ___
=cut

sub delete_rec {
  my ( $self, $store, $table, $mapping, $id ) = @_;
  my $class = $store->resultset($table);
  my ($pk) = $class->result_source->primary_columns();

  my $txxxxxxref = sub {
    my $record = $class->find( { $pk => $id } );
    unless ($record) {
      DBIx::Class::Exception->throw('[[Record not found!]]');
    }
    if (blessed($record) and $record->can('complex_delete') ) {
      $record->complex_delete($id);
    }
    return $record->delete();
  };

  my $record;
  try {
    $record = $store->txn_do($txxxxxxref);
  }
  catch {
    DBIx::Class::Exception->throw( '[[Record could not be deleted!]]: Reason:' . $_ );
  };

  return 1;
}

register create_record       => \&create_rec;
register read_record         => \&read_rec;
register update_record       => \&update_rec;
register delete_record       => \&delete_rec;
register register_new_record => \&register_rec;

register_plugin for_versions => [ 1, 2 ];

1;
