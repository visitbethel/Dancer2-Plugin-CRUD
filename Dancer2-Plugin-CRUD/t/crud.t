use strict;
use warnings;

use Test::More;
use Plack::Test;
use HTTP::Request::Common;

subtest 'pass within routes' => sub {
  {

    package App;
    use lib './t/lib';
    use Dancer2;
    use Test::More;
    use Dancer2::Plugin::DBIC qw(schema resultset rset);
    set plugins => {
                     DBIC => {
                               CRUD => {
                                         schema_class => 'CRUD',
                                         dsn => 'dbi:SQLite:dbname=:memory:',
                               },
                     },
                     CRUD => {
                          mapping => 'territory'
                     },
                     
    };
    my $store  = schema 'CRUD';
    $store->deploy;
    my $parent = $store->resultset('Parent');
    ok( $parent, "validate" );
    $store->resultset('Parent')->create(
                     {
                       name      => 'adam',
                       last_name => 'unknown'
                     }
    );

    my $adam = $store->resultset('Parent')->find(1);
    ok( $adam, "created new record" );
    is( $adam->name, 'adam', 'name of new record' );

    get '/'   => sub { 'hello' };

    get '/pass' => sub {
      return "the baton";
    };
    get '/template_extension' => sub {
      return engine('template')->default_tmpl_ext;
    };

    get '/parent/:number' => sub {
      my $store = schema 'CRUD';
      $store->resultset('Parent')->find( param 'number');
      return template 'index';
    };

    get '/appviewspartial' => sub {
      return template 'views/partial';
    };
    
#    get '/**' => sub {
#      header 'X-Pass' => 'pass';
#      pass;
#      redirect '/';    # won't get executed as pass returns immediately.
#    };    
  }

  my $app = Dancer2->runner->psgi_app;
  is( ref $app, 'CODE', 'Got app' );

  plan skip_all => 'DBD::SQLite required to run these tests' if $@;

  test_psgi $app, sub {
    my $cb = shift;

    {
      my $res = $cb->( GET '/pass' );
      is( $res->code,    200,         '[/pass] Correct status' );
      is( $res->content, 'the baton', '[/pass] Correct content' );

      my $res2 = $cb->( GET '/template_extension' );
      is( $res2->code,    200,  '[/template_extension] Correct status' );
      is( $res2->content, 'tt', '[/template_extension] Correct content' );

      $res2 = $cb->( GET '/parent/1');
      is( $res2->code,    200,  '[/parent/1] Correct status' );
      is( $res2->content, '{ name: admin, last_name: unknown }', '[/parent/1] Correct content' );
      
   #
   #      my $res3 = $cb->( GET '/appindex' );
   #      is( $res3->code,    200,     '[/appindex] Correct status' );
   #      is( $res3->content, 'INDEX', '[/appindex] Correct content' );
   #
   #      my $res4 = $cb->( GET '/appviewspartial' );
   #      is( $res4->code,    200,       '[/appviewspartial] Correct status' );
   #      is( $res4->content, 'PARTIAL', '[/appviewspartial] Correct content' );
    }
  };

};

done_testing;
