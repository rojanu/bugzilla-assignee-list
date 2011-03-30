# -*- Mode: perl; indent-tabs-mode: nil -*-
#
# The contents of this file are subject to the Mozilla Public
# License Version 1.1 (the "License"); you may not use this file
# except in compliance with the License. You may obtain a copy of
# the License at http://www.mozilla.org/MPL/
#
# Software distributed under the License is distributed on an "AS
# IS" basis, WITHOUT WARRANTY OF ANY KIND, either express or
# implied. See the License for the specific language governing
# rights and limitations under the License.
#
# The Original Code is the AssigneeList Bugzilla Extension.
#
# The Initial Developer of the Original Code is Ali Ustek
# Portions created by the Initial Developer are Copyright (C) 2011 the
# Initial Developer. All Rights Reserved.
#
# Contributor(s):
#   Ali Ustek <aliustek@gmail.com>

package Bugzilla::Extension::AssigneeList;
use strict;
use base qw(Bugzilla::Extension);
use Bugzilla::Util qw(get_text);

use Bugzilla::Constants;
use Bugzilla::Error;
use Bugzilla::Token;
use Bugzilla::Util;
use Carp;


use Bugzilla::Extension::AssigneeList::Constants;
use Bugzilla::Extension::AssigneeList::Group;
use Bugzilla::Extension::AssigneeList::Assignee;

our $VERSION = '0.01';

BEGIN {
   *Bugzilla::Component::assignees = \&_assignees;
   *Bugzilla::Component::assignee_groups = \&_assignee_groups;
   *Bugzilla::Product::user_can_see = \&_user_can_see;
}

###########################
# Database & Installation #
###########################

sub db_schema_abstract_schema {
    my ($self, $args) = @_;

    $args->{'schema'}->{'componentleadsgroup'} = {
        FIELDS => [
        	id                      => {TYPE => 'MEDIUMSERIAL', NOTNULL => 1, PRIMARYKEY => 1},
            component_id  => {TYPE => 'INT2', NOTNULL => 1,
                                             REFERENCES => {TABLE  => 'components',
                                                                           COLUMN => 'id',
                                                                           DELETE => 'CASCADE'}},
            name         => {TYPE => 'varchar(64)', NOTNULL => 1},
            sortkey       => {TYPE => 'INT2', NOTNULL => 1, DEFAULT => 0},
        ],
        INDEXES => [
        	componentleadsgroup_name_component_id_idx => 
                {FIELDS => [qw(component_id name)], TYPE => 'UNIQUE'},
            componentleadsgroup_sortkey_idx => ['sortkey'],
        ],
    };

    $args->{'schema'}->{'componentleads'} = {
        FIELDS => [
            id			            => {TYPE => 'MEDIUMSERIAL', NOTNULL => 1, PRIMARYKEY => 1},
            user_id            => {TYPE  => 'INT3', NOTNULL => 1,
                                            REFERENCES => {TABLE  => 'profiles',
                                                                          COLUMN => 'userid',
                                                                          DELETE => 'CASCADE'}},
            group_id           => {TYPE => 'INT3', NOTNULL => 1,
                                             REFERENCES => {TABLE  => 'componentleadsgroup',
                                                                           COLUMN => 'id',
                                                                           DELETE => 'CASCADE'}},
            name                  => {TYPE => 'varchar(64)', NOTNULL => 1},
            sortkey              => {TYPE => 'INT2', NOTNULL => 1, DEFAULT => 0},
        ],
        INDEXES => [
            componentleads_id_idx => 
                {FIELDS => [qw(group_id user_id)], TYPE => 'UNIQUE'},
            componentleads_group_id_idx => ['group_id'],
            componentleads_sortkey_idx => ['sortkey'],
        ],
    };
}

#########
# Pages #
#########

sub template_before_create {
    my ($self, $args) = @_;
    my $config = $args->{'config'};

    my $constants = $config->{CONSTANTS};
    $constants->{MAX_LABEL_LENGTH} = MAX_LABEL_LENGTH;
}

sub page_before_template {
    my ($self, $args) = @_;
    my $page = $args->{page_id};
    my $vars = $args->{vars};
    
    if ($page =~ m{^assigneelist/.*}) {
        
        my $cgi = Bugzilla->cgi;
    	my $template = Bugzilla->template;

        #
    	# Preliminary checks:
    	#

    	my $user = Bugzilla->login(LOGIN_REQUIRED);
    	print $cgi->header();
        
        $user->in_group('editcomponents')
          || scalar(@{$user->get_products_by_permission('editcomponents')})
          || ThrowUserError("auth_failure", {group  => "editcomponents",
                                             action => "edit",
                                             object => "components"});
    	#
    	# often used variables
    	#
    	my $product_name  = trim($cgi->param('product')     || '');
    	my $comp_name     = trim($cgi->param('component')   || '');
    	my $action        = trim($cgi->param('action')      || '');
    	my $showbugcounts = (defined $cgi->param('showbugcounts'));

    	#
    	# product = '' -> Show nice list of products
    	#
    	unless ($product_name) {
        	my $selectable_products = $user->get_selectable_products;
    	    # If the user has editcomponents privs for some products only,
    	    # we have to restrict the list of products to display.
    	    unless ($user->in_group('editcomponents')) {
    	        $selectable_products = $user->get_products_by_permission('editcomponents');
        	}
    	    $vars->{'products'} = $selectable_products;
        	$vars->{'showbugcounts'} = $showbugcounts;

        	$template->process("admin/components/select-product.html.tmpl", $vars)
    	      || ThrowTemplateError($template->error());
        	exit;
    	}

    	my $product = $user->check_can_admin_product($product_name);

    	#
    	# comp_name='' -> Show nice list of components
    	#

    	unless ($comp_name) {
    	    $vars->{'showbugcounts'} = $showbugcounts;
        	$vars->{'product'} = $product;
    	    $template->process("admin/components/list.html.tmpl", $vars)
        	    || ThrowTemplateError($template->error());
    	    exit;
    	}
    	
       	$vars->{'comp'} =
		Bugzilla::Component->check({ product => $product, name => $comp_name });
        $vars->{'product'} = $product;

    	#
    	# User can edit given component, goto page requested
    	#
        if ($page =~ m{^assigneelist/list\.}) {
            _page_assignees($vars, $action);
        }
        elsif ($page =~ m{^assigneelist/group/list\.}) {
            _page_assigneegroups($vars, $action);
        }
    }
}

# Method to take care of all Assigne actions
sub _page_assignees {
    my ($vars, $action) = @_;
	my $template = Bugzilla->template;
	my $cgi = Bugzilla->cgi;
	my $token         = $cgi->param('token');
	
	if ($action eq '' || $action eq 'list') {
        $template->process("pages/assigneelist/list.html.tmpl", $vars)
            || ThrowTemplateError($template->error());
        exit;
    }

    if ($action eq 'add') {
        $vars->{'token'} = issue_session_token('add_assignee');
        $template->process("pages/assigneelist/create.html.tmpl", $vars)
            || ThrowTemplateError($template->error());
        exit;
    }

    if ($action eq 'new') {
	    my $group = new Bugzilla::Extension::AssigneeList::Group($cgi->param('group'));
	    my $user = new Bugzilla::User({name => $cgi->param('user_login')});

        my $assignee = Bugzilla::Extension::AssigneeList::Assignee->create({
                                      name => $cgi->param('name'), 
                                    sortkey => $cgi->param('sortkey'),
                                         user => $user,
                                       group => $group,
                                 });
    
        $vars->{'message'} = 'assignee_created';
        $vars->{'assignee'} = $assignee;
        delete_token($token);

        $template->process("pages/assigneelist/list.html.tmpl", $vars)
            || ThrowTemplateError($template->error());
        exit;
    }

    # After this point changes are made to an existing assignee
    my $assignee = new Bugzilla::Extension::AssigneeList::Assignee($cgi->param('assignee_id'));
	$vars->{'assignee'} = $assignee;

    if ($action eq 'update') {
	    check_token_data($token, 'edit_assignee');
	    
	    my $group = new Bugzilla::Extension::AssigneeList::Group($cgi->param('group'));

        $assignee->set_name($cgi->param('name_new'));
        $assignee->set_group($group);
        $assignee->set_sortkey($cgi->param('sortkey'));
        my $changes = $assignee->update();

        $vars->{'message'} = 'assignee_updated';
        $vars->{'changes'} = $changes;
        delete_token($token);
        $template->process("pages/assigneelist/list.html.tmpl", $vars)
            || ThrowTemplateError($template->error());
        exit;
    }

    if ($action eq 'del') {
        $vars->{'token'} = issue_session_token('delete_assignee');
        $template->process("pages/assigneelist/confirm-delete.html.tmpl", $vars)
            || ThrowTemplateError($template->error());
        exit;
    }
    
    if ($action eq 'delete') {
	    check_token_data($token, 'delete_assignee');
	    
	    $assignee->remove_from_db;
	    
	    $vars->{'message'} = 'assignee_deleted';
        $template->process("pages/assigneelist/list.html.tmpl", $vars)
            || ThrowTemplateError($template->error());
        exit;
    }

    if ($action eq 'edit') {
        $vars->{'token'} = issue_session_token('edit_assignee');
        $template->process("pages/assigneelist/edit.html.tmpl", $vars)
            || ThrowTemplateError($template->error());
        exit;
    }
    
    # No valid action found
	ThrowUserError('unknown_action', {action => $action});
}

# Method to take care of all AssigneGroup actions
sub _page_assigneegroups {
    my ($vars, $action) = @_;
	my $template = Bugzilla->template;
	my $cgi = Bugzilla->cgi;
	my $token         = $cgi->param('token');
	
	if ($action eq '' || $action eq 'list') {
        $template->process("pages/assigneelist/group/list.html.tmpl", $vars)
            || ThrowTemplateError($template->error());
        exit;
    }

    if ($action eq 'add') {
        $vars->{'token'} = issue_session_token('add_assignee_group');
        $template->process("pages/assigneelist/group/create.html.tmpl", $vars)
            || ThrowTemplateError($template->error());
        exit;
    }

    if ($action eq 'new') {
        my $group = Bugzilla::Extension::AssigneeList::Group->create({
        							name => $cgi->param('name'), 
                                    sortkey => $cgi->param('sortkey'),
                                    component => $vars->{'comp'}
                                 });
    
        $vars->{'message'} = 'assignee_group_created';
        $vars->{'group'} = $group;
        delete_token($token);

        $template->process("pages/assigneelist/group/list.html.tmpl", $vars)
            || ThrowTemplateError($template->error());
        exit;
    }

    # After this point changes are made to an existing group
    my $group = new Bugzilla::Extension::AssigneeList::Group({ 
    														component => $vars->{'comp'}, 
    														name => $cgi->param('name')
														});
	$vars->{'group'} = $group;

    if ($action eq 'del') {
        $vars->{'token'} = issue_session_token('delete_assignee_group');
        $template->process("pages/assigneelist/group/confirm-delete.html.tmpl", $vars)
            || ThrowTemplateError($template->error());
        exit;
    }
    
    if ($action eq 'delete') {
	    check_token_data($token, 'delete_assignee_group');
	    
	    $group->remove_from_db;
	    
	    $vars->{'message'} = 'assignee_group_deleted';
        $template->process("pages/assigneelist/group/list.html.tmpl", $vars)
            || ThrowTemplateError($template->error());
        exit;
    }

    if ($action eq 'edit') {
        $vars->{'token'} = issue_session_token('edit_assignee_group');
        $template->process("pages/assigneelist/group/edit.html.tmpl", $vars)
            || ThrowTemplateError($template->error());
        exit;
    }

    if ($action eq 'update') {
	    check_token_data($token, 'edit_assignee_group');

        $group->set_name($cgi->param('name_new'));
        $group->set_sortkey($cgi->param('sortkey'));
        my $changes = $group->update();

        $vars->{'message'} = 'assignee_group_updated';
        $vars->{'changes'} = $changes;
        delete_token($token);
        $template->process("pages/assigneelist/group/list.html.tmpl", $vars)
            || ThrowTemplateError($template->error());
        exit;
    }
    
    # No valid action found
	ThrowUserError('unknown_action', {action => $action});
}

############################
# Component Object Methods #
############################
sub _assignees {
    my $self = shift;
    my $dbh = Bugzilla->dbh;

    if (!defined $self->{assignees}) {
        my $ids = $dbh->selectcol_arrayref(q{
            SELECT L.id FROM componentleads AS L
            LEFT JOIN componentleadsgroup AS G ON G.id = L.group_id
            WHERE G.component_id = ?
            ORDER BY L.group_id, L.sortkey}, undef, $self->id);

        require Bugzilla::Extension::AssigneeList::Assignee;
        $self->{assignees} = Bugzilla::Extension::AssigneeList::Assignee->new_from_list($ids);
    }
    return $self->{assignees};
}

sub _assignee_groups {
    my $self = shift;
    my $dbh = Bugzilla->dbh;

    if (!defined $self->{assignee_groups}) {
        my $ids = $dbh->selectcol_arrayref(q{
            SELECT id FROM componentleadsgroup
            WHERE component_id = ?
            ORDER BY sortkey}, undef, $self->id);

        require Bugzilla::Extension::AssigneeList::Group;
        $self->{assignee_groups} = Bugzilla::Extension::AssigneeList::Group->new_from_list($ids);
    }
    return $self->{assignee_groups};
}

##########################
# Product Object Methods #
##########################

sub _user_can_see {
    my $self = shift;
    require Bugzilla::User;
    my @custusers;
    my @allusers = @{Bugzilla->user->get_userlist};
    foreach my $user (@allusers) {
        my $user_obj = new Bugzilla::User({name => $user->{login}});
        push(@custusers, $user) if $user_obj->can_see_product($self->name);
    }
    return \@custusers;
}

##########################

__PACKAGE__->NAME;

=head1 NAME

Bugzilla::Extension::AssigneeList - Object for a Bugzilla AssigneeList extension.

=head1 SYNOPSIS

    my @assignees      = $componet->assignees();
    my @assignee_groups      = $componet->assignee_groups();
    my @visible_to_users        = $product->visible_to_users();

=head1 DESCRIPTION

This package converts bug assignee field to a list of users to select assignee from,
each component would have a list of user to whom bugs can be assinged.

The methods that are added to other Bugzilla classes are listed below.

=head2 Custom Added Methods

=item C<assignees()>

 Description: Returns an array of assignee objects belonging to the component.

 Params:      none.

 Returns:     An array of Bugzilla::Extension::AssigneeList::Assignee object.
 
=item C<assignee_groups()>

 Description: Returns an array of Assignee Group objects belonging to the component.
 
 Params:      none
 
 Returns:     An array of Bugzilla::Extension::AssigneeList::Group object.

=item C<user_can_see()>

 Description: Returns an array of User objects whom the product is visible.
 
 Params:      none
 
 Returns:      An array of Bugzilla::User object.

=back

=head1 SEE ALSO

L<Bugzilla::Component>
L<Bugzilla::Product>
L<Bugzilla::User>
