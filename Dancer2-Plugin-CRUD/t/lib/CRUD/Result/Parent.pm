use utf8;
package CRUD::Result::Parent;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

CRUD::Result::Parent

=cut

use strict;
use warnings;

use Moose;
use MooseX::NonMoose;
use MooseX::MarkAsMethods autoclean => 1;
extends 'DBIx::Class::Core';

=head1 COMPONENTS LOADED

=over 4

=item * L<DBIx::Class::InflateColumn::DateTime>

=back

=cut

__PACKAGE__->load_components("InflateColumn::DateTime");

=head1 TABLE: C<PARENT>

=cut

__PACKAGE__->table("PARENT");

=head1 ACCESSORS

=head2 id

  data_type: 'integer'
  is_auto_increment: 1
  is_nullable: 0

=head2 name

  data_type: 'text'
  is_nullable: 0

=head2 last_name

  data_type: 'text'
  is_nullable: 0

=head2 child

  data_type: 'integer'
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "id",
  { data_type => "integer", is_auto_increment => 1, is_nullable => 0 },
  "name",
  { data_type => "text", is_nullable => 0 },
  "last_name",
  { data_type => "text", is_nullable => 0 },
  "child",
  { data_type => "integer", is_nullable => 1 },
);

=head1 PRIMARY KEY

=over 4

=item * L</id>

=back

=cut

__PACKAGE__->set_primary_key("id");

=head1 UNIQUE CONSTRAINTS

=head2 C<name_last_name_unique>

=over 4

=item * L</name>

=item * L</last_name>

=back

=cut

__PACKAGE__->add_unique_constraint("name_last_name_unique", ["name", "last_name"]);

=head1 RELATIONS

=head2 children

Type: has_many

Related object: L<CRUD::Result::Child>

=cut

__PACKAGE__->has_many(
  "children",
  "CRUD::Result::Child",
  { "foreign.parent" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);


# Created by DBIx::Class::Schema::Loader v0.07035 @ 2014-07-30 13:16:48
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:PLp9fqfEhuHuLtNw0Zhx8A


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
