package Dancer2::Plugin::Pagination;

use strict;
use warnings;
use Dancer2;
use Dancer2::Plugin;
use Dancer2::Logger::Console;
use Data::Dumper;
use Carp qw/carp/;
use Dancer2::Plugin::MapperUtils qw/map_fields/;
use JSON::PP qw(encode_json decode_json);
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
	
	unless ($map) {
		carp( "missing mapping for lookup of " . $table );
	}
	
	my $columm_map = $columns ? { columns => $columns } : $columns;
	return &map_fields( $map,
		$store->resultset($table)->search( $where, $columm_map ) );
}

=head
  ------------- mapper -------------  ------------- 
=cut

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
  ------------- map field -------------  ------------- 
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
				printf "HASH : %s->%s baging ref(%s)\n", $method, $hashkeys,
				  ref( $base->$hashkeys )
				  if $DEBUG_RESULTSET
					  and $DEBUG_MAPPING;
			}

			#&logf(Dumper( \%bag ));
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
				printf "ARRAY: %s->%s baging ref(%s)\n", $method, $hashkeys,
				  ref( $base->$hashkeys )
				  if $DEBUG_RESULTSET
					  and $DEBUG_MAPPING;
			}

			#&logf(Dumper( \%bag ));
			$value = \%bag;
		}
		else {
			$value = undef;
		}
	}
}

=head
  ------------- pagination -------------  ------------- 
=cut

sub pagination {
	my ( $self, $store, $table, $mapping, $subselect, $preselect,
		$calculated_sub )
	  = @_;

	my %params = $self->params;
	&logf( "PARAMS:" . Dumper( \%params ) );
	unless ($mapping) {
		die( "missing mapping for " . $table );
		return 1;
	}

	# deserialize the filter, page and sort options.
	my $pager =
	  $self->params->{'pager'} ? decode_json( $self->params->{'pager'} ) : {};
	my $filter =
	  $self->params->{'filter'} ? decode_json( $self->params->{'filter'} ) : {};
	my $sort =
	  $self->params->{'sort'} ? decode_json( $self->params->{'sort'} ) : {};

	my $limit      = $pager  && $pager->{'pageSize'}     || $DEFAULT_PAGE_SIZE;
	my $pagenr     = $pager  && $pager->{'currentPage'}  || 1;
	my $type       = $filter && $filter->{'matchType'}   || 'any';
	my $text       = $filter && $filter->{'filterText'}  || '';
	my $field      = $filter && $filter->{'matchFields'} || ['name'];
	my $ignorecase = $filter && $filter->{'ignorecase'}  || 1;
	my $wildcard   = $filter && $filter->{'wildcard'}    || 1;
	my $sortFields = $sort   && $sort->{'field'};
	my $sortDirection = $sort && $sort->{'direction'} || ['ASC'];

	# establish default filtering
	my @column  = ();
	my %rev     = reverse %{$mapping};
	my %sortrev = ();
	foreach my $r ( keys %{$mapping} ) {
		if ( ref $mapping->{$r} eq 'HASH' ) {
			foreach my $sr ( keys %{ $mapping->{$r} } ) {
				$sortrev{ sprintf "%s.%s", $r, $mapping->{$r}->{$sr} } = $sr;
			}
		}
		else {
			$sortrev{ $mapping->{$r} } = $r;
		}
	}
	#print "SORTREV", Dumper( \%sortrev );

	foreach my $expr (@$field) {
		my ( $k, $dbfield ) = split /\./, $expr;    #/
		printf "k=%s, field=%s  [%s]\n", $k, $dbfield ? $dbfield : 'NA', $expr;
		if ($dbfield) {
			my %rmap = reverse %{ $mapping->{$k} };
			push @column, $rmap{$dbfield};
		}
		else {
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
					if ($wildcard) {
						$where{"LOWER(me.$f)"}{'-like'} = '%' . lc $text . '%';
					}
					else {
						$where{"LOWER(me.$f)"}{'-like'} = lc $text . '%';
					}
				}
				else {
					if ($wildcard) {
						$where{"me.$f"}{'-like'} = '%' . $text . '%';
					}
					else {
						$where{"me.$f"}{'-like'} = $text . '%';
					}
				}

			}
		}
		else {
			&logf( "<><<<<<<<<<<<<<<<<<"
				  . Dumper( $text, \@column, \@$field, $mapping ) )
			  if $DEBUG_RESULTSET;
			if ( scalar @column > 1 ) {
				foreach my $f (@column) {
					next unless $f;
					if ($ignorecase) {
						if ($wildcard) {
							push @{ $where{'-or'} },
							  { "LOWER(me.$f)" =>
								  { '-like' => '%' . lc $text . '%' } };
						}
						else {
							push @{ $where{'-or'} },
							  { "LOWER(me.$f)" => { '-like' => lc $text . '%' }
							  };
						}
					}
					else {
						if ($wildcard) {
							push @{ $where{'-or'} },
							  { "me.$f" => { '-like' => '%' . $text . '%' } };

						}
						else {
							push @{ $where{'-or'} },
							  { "me.$f" => { '-like' => $text . '%' } };

						}
					}

				}
			}
			else {
				foreach my $f (@column) {
					next unless $f;
					if ($ignorecase) {
						if ($wildcard) {
							$where{"LOWER(me.$f)"}{'-like'} =
							  '%' . lc $text . '%';
						}
						else {
							$where{"LOWER(me.$f)"}{'-like'} = lc $text . '%';
						}
					}
					else {
						if ($wildcard) {
							$where{"me.$f"}{'-like'} = '%' . $text . '%';
						}
						else {
							$where{"me.$f"}{'-like'} = $text . '%';
						}

					}
				}
			}
		}
	}
	my @order = ();

	#@order = map { $mapping->{$_} . ' ASC' } @$sortFields if $sortFields;
	foreach my $fld ( @{$sortFields} ) {
		if ( $fld && $sortrev{$fld} ) {
			my $fld = sprintf "%s %s", $sortrev{$fld},
			  $sortDirection->[0];
			push @order, $fld;
		}
		else {
			print Dumper("missing rev{$fld}") if $fld;
			print Dumper( \%sortrev );
		}
	}
	#print Dumper( ">>>sorting:", $sort, $sortFields, \@order );

	my %options = (
		page     => $pagenr,
		rows     => $limit,
		order_by => \@order

	);
	if ( $subselect and ref($subselect) eq 'HASH' ) {
		%options = ( %options, %$subselect );
	}
	&logf( "OPTIONS:" . Dumper( \%options ) );
	&logf( "WHERE  : " . Dumper( \%where ) );
	&logf( "ORDER  : " . Dumper( \@order ) );
	my @rs = $store->resultset($table)->search( \%where, \%options );
	my $count = $store->resultset($table)->search( \%where )->count;

	my $result = &map_fields( $mapping, @rs, $calculated_sub );
	&logf( "return " . scalar @$result . " of " . $count . " records.\n" );

	#&logf(Dumper($result));
	return { 'totalItems' => $count, 'items' => $result };
}

=head
  ------------- merge pages / union -------------  ------------- 
=cut

sub merge_pagers {
	my %resultset = ( 'totalItems' => 0, 'items' => [] );
	foreach my $set (@_) {
		if ( $set and ref($set) eq 'HASH' and $set->{'totalItems'} ) {
			$resultset{'totalItems'} += $set->{'totalItems'};
			my @list = @{ $set->{'items'} };
			print "\n>>>>>>>>>>>>>", ref( $resultset{'items'} );
			my @totallist = @{ $resultset{'items'} };
			@list = ( @list, @totallist );
			$resultset{'items'} = \@list;
		}
	}
	return \%resultset;
}

sub logf {
	printf @_ if $DEBUG_MAPPING;
}

register get_lookups  => \&get_lookups;
register pager        => \&pagination;
register merge_pagers => \&merge_pagers;
register mapper       => \&mapper;
register_plugin for_versions => [ 1, 2 ];

1;
