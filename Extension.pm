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

our $VERSION = '0.01';

BEGIN {
   *Bugzilla::Component::assignees = \&assignees;
   *Bugzilla::Component::assignee_groups = \&assignee_groups;
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
            component_id  => {TYPE => 'INT2', NOTNULL => 1,
                                             REFERENCES => {TABLE  => 'components',
                                                                           COLUMN => 'id',
                                                                           DELETE => 'CASCADE'}},
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
                {FIELDS => [qw(component_id user_id)], TYPE => 'UNIQUE'},
            omponentleads_group_id_idx => ['group_id'],
            componentleads_sortkey_idx => ['sortkey'],
        ],
    };
}

#########
# Pages #
#########

sub template_constants {
    my ($self,  $args) = @_;
    $args->{constants}{MAX_LABEL_LENGTH} = MAX_LABEL_LENGTH;
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

    	$vars->{'product'} = $product;
    	$vars->{'comp'} =
            Bugzilla::Component->check({ product => $product, name => $comp_name });

    	#
    	# User can edit given component, goto page requested
    	#
        if ($page =~ m{^assigneelist/\.}) {
            _page_assignees($vars);
        }
        elsif ($page =~ m{^assigneelist/group/list\.}) {
            _page_assigneegroups($vars, $action);
        }
    }
}

sub _page_assignees {
    my ($vars) = @_;
}

sub _page_assigneegroups {
    my ($vars, $action) = @_;
	my $template = Bugzilla->template;
	my $cgi = Bugzilla->cgi;

    if ($action eq 'add') {
        $vars->{'token'} = issue_session_token('add_assignee_group');
        $template->process("pages/assigneelist/group/create.html.tmpl", $vars)
            || ThrowTemplateError($template->error());
        exit;
    }

    #
    # action='new' -> add component assignee group
    #
    if ($action eq 'new') {
	    my $name     = $cgi->param('name');
	    my $sortkey = $cgi->param('sortkey');
        my $token     = $cgi->param('token');

        my $group = Bugzilla::Extension::AssigneeList::Group->create({
        							name =>$name, 
                                    sortkey => $sortkey,
                                    component_id => $vars->{'comp'}->id ,
                                 });
    
        $vars->{'message'} = 'assignee_group_created';
        $vars->{'group'} = $group;
        delete_token($token);

        $template->process("pages/assigneelist/group/list.html.tmpl", $vars)
            || ThrowTemplateError($template->error());
        exit;
    }

    #
    # action='edit' -> edit component assignee group
    #
    if ($action eq 'edit') {
	    my $group_id = $cgi->param('group_id');

        $vars->{'group'} = new Bugzilla::Extension::AssigneeList::Group($group_id);

        $vars->{'token'} = issue_session_token('edit_assignee_group');
        $template->process("pages/assigneelist/group/edit.html.tmpl", $vars)
            || ThrowTemplateError($template->error());
        exit;
    }
}

############################
# Component Object Methods #
############################
sub assignees {
    my $self = shift;
    my $dbh = Bugzilla->dbh;

    if (!defined $self->{assignees}) {
        my $ids = $dbh->selectcol_arrayref(q{
            SELECT id FROM componentleads
            WHERE component_id = ?
            ORDER BY group_id,sortkey}, undef, $self->id);

        require Bugzilla::Extension::AssigneeList::Assignee;
        $self->{assignees} = Bugzilla::Extension::AssigneeList::Assignee->new_from_list($ids);
    }
    return $self->{assignees};
}

sub assignee_groups {
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

__PACKAGE__->NAME;
