package Dancer2::Plugin::Pagination;

use strict;
use warnings;
use Dancer2;
use Dancer2::Plugin;
use Dancer2::Logger::Console;
use Data::Dumper;
use Dancer2::Plugin::MapperUtils qw/map_fields/;
use Scalar::Util qw(blessed);

our $AUTHORITY         = 'KAAN';
our $VERSION           = '0.01';
our $DEFAULT_PAGE_SIZE = 5;
our $DEBUG_RESULTSET   = 0;
our $DEBUG_MAPPING     = 0;
our $logger            = Dancer2::Logger::Console->new;

=head

Define a hash with the field to json mapping.
  'project' => {
                 'name'     => 'project_nm',
                 'id'       => 'project_seq',
                 'abbrev'   => 'project_acronym',
                 'status'   => 'status_cd',
                 'sym_id'   => 'symphony_id',
                 'sym_name' => 'symphony_nm'
  },
Then use the pager like this... 


get '/project/:page' => sub {
  my $store = schema 'default';
  return pager( $store, 'Project', $mapping{'project'} );
};


The controller or service will send the following: 

angular.module('yabfApp').factory('projectService', function($http) {

  var projectAPI = {};

  projectAPI.search = function(pageOpts, filterOpts, sortOpts) {
    return $http.get('/project/1', {
      params : {
        'filter' : filterOpts && angular.toJson(filterOpts) || '',
        'pager' : pageOpts && angular.toJson(pageOpts) || '',
        'sort' : sortOpts && angular.toJson(sortOpts) || ''
      }
    });
  };
  return projectAPI;

});

THe options are defined in the ng-grid on the controller.
          $scope.gridOptions = {
            data : 'list',
            enableRowSelection : true,
            enablePaging : true,
            enableCellEditOnFocus : true,
            showFilter : false,
            showGroupPanel : true,
            showFooter : true,
            filterOptions : $scope.filterOptions,
            pagingOptions : $scope.pagingOptions,
            sortInfo : $scope.sortOptions,
            multiSelect : false,
..
..
        }
        
          $scope.filterOptions = {
            useExternalFilter : true,
            filterText : "",
            show : false,
            matchType : 'any',
            matchFields : {
              'name' : true,
              'abbrev' : true
            },
            fields : [ {
              id : 'name',
              desc : 'Name'
            }, {
              id : 'abbrev',
              desc : 'Acronym'
            } ]
          };

          $scope.pagingOptions = {
            pageSizes : [ 25, 50, 100 ],
            pageSize : 5,
            currentPage : 1
          };
          $scope.sortOptions = {
            fields : [ "name" ],
            directions : [ "ASC" ]
          };

=cut

sub get_lookups {
  my ( $self, $store, $table, $map, $where, $columns ) = @_;
  my $columm_map = $columns ? { columns => $columns } : $columns;
  return &map_fields( $map, $store->resultset($table)->search( $where, $columm_map ) );
}

sub mapper {
  my ( $self, $defs, @rs ) = @_;
  return &map_fields( $defs, @rs );
}

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
    $base = $base->$method if $base;
    printf "      : %s->%s traverse\n", 'base', $method
      if $DEBUG_RESULTSET
        and $DEBUG_MAPPING;
    return $base;
  }
  elsif ( ref($method) eq 'HASH' ) {

    # if there is a base find its path values.
    if ($base) {

      # array ref, multiple values in one
      my %bag = ();
      foreach my $hashkeys ( keys %{$method} ) {
        $bag{ $method->{$hashkeys} } = $base->$hashkeys;
        printf "HASH : %s->%s baging ref(%s)\n", $method, $hashkeys, ref( $base->$hashkeys )
          if $DEBUG_RESULTSET
            and $DEBUG_MAPPING;
      }

      #print Dumper( \%bag );
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
        printf "ARRAY: %s->%s baging ref(%s)\n", $method, $hashkeys, ref( $base->$hashkeys )
          if $DEBUG_RESULTSET
            and $DEBUG_MAPPING;
      }

      #print Dumper( \%bag );
      $value = \%bag;
    }
    else {
      $value = undef;
    }
  }
}

sub pagination {
  my ( $self, $store, $table, $mapping, $subselect, $preselect, $calculated_sub ) = @_;

  my %params = $self->params;
  print "PARAMS:" . Dumper( \%params );
  unless ($mapping) {
    die( "missing mapping for " . $table );
    return 1;
  }

  # deserialize the filter, page and sort options.
  my $pager  = $self->from_json( $self->params->{'pager'} );
  my $filter = $self->from_json( $self->params->{'filter'} );
  my $sort   = $self->from_json( $self->params->{'sort'} );

  my $limit         = $pager  && $pager->{'pageSize'}     || $DEFAULT_PAGE_SIZE;
  my $pagenr        = $pager  && $pager->{'currentPage'}  || 1;
  my $type          = $filter && $filter->{'matchType'}   || 'any';
  my $text          = $filter && $filter->{'filterText'}  || '';
  my $field         = $filter && $filter->{'matchFields'} || ['name'];
  my $ignorecase    = $filter && $filter->{'ignorecase'}  || 1;
  my $sortFields    = $sort   && $sort->{'fields'};
  my $sortDirection = $sort   && $sort->{'directions'}    || ['ASC'];

  # establish default filtering
  my @column = ();

  foreach my $expr (@$field) {
    my ( $k, $dbfield ) = split /\./, $expr;    #/
    printf "k=%s, field=%s  [%s]\n", $k, $dbfield ? $dbfield : 'NA', $expr;
    if ($dbfield) {
      my %rmap = reverse %{ $mapping->{$k} };
      push @column, $rmap{$dbfield};
    }
    else {
      my %rev = reverse %{$mapping};
      push @column, $rev{$k};
    }
  }

  #
  #  my @column = keys %column;
  #die Dumper($field) . " and " . Dumper(\@column);
  #
  my %where = $preselect ? %{$preselect} : ();
  if ( $text ne '' ) {
    if ( $type =~ /all/ ) {
      foreach my $f (@column) {
        next unless $f;
        if ($ignorecase) {
          $where{"LOWER(me.$f)"}{'-like'} = lc $text . '%';
        }
        else {
          $where{"me.$f"}{'-like'} = $text . '%';
        }

      }
    }
    else {
      print "<><<<<<<<<<<<<<<<<<" . Dumper( $text, \@column, \@$field, $mapping ) if 0 > 1;
      if ( scalar @column > 1 ) {
        foreach my $f (@column) {
          next unless $f;
          if ($ignorecase) {
            push @{ $where{'-or'} }, { "LOWER(me.$f)" => { '-like' => lc $text . '%' } };
          }
          else {
            push @{ $where{'-or'} }, { "me.$f" => { '-like' => $text . '%' } };
          }

        }
      }
      else {
        foreach my $f (@column) {
          next unless $f;
          if ($ignorecase) {
            $where{"LOWER(me.$f)"}{'-like'} = $text . '%';
          }
          else {
            $where{"me.$f"}{'-like'} = $text . '%';

          }
        }
      }
    }
  }
  my @order = ();

  #@order = map { $mapping->{$_} . ' ASC' } @$sortFields if $sortFields;

  my %options = (
    page     => $pagenr,
    rows     => $limit,
    order_by => \@order

  );
  if ( $subselect and ref($subselect) eq 'HASH' ) {
    %options = ( %options, %$subselect );
  }
  print "OPTINS:" . Dumper( \%options );
  print "WHERE : " . Dumper( \%where );
  print "ORDER : " . Dumper( \@order );
  my @rs = $store->resultset($table)->search( \%where, \%options );
  my $count = $store->resultset($table)->search( \%where )->count;

  my $result = &map_fields( $mapping, @rs, $calculated_sub );
  print "return " . scalar @$result . " of " . $count . " records.\n";

  #print Dumper($result);
  return { 'totalItems' => $count, 'items' => $result };
}

register get_lookups => \&get_lookups;
register pager       => \&pagination;
register mapper      => \&mapper;
register_plugin for_versions => [ 1, 2 ];

1;
