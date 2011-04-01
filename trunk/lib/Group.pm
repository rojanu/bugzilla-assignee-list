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
#   Ali Ustek <AliUstek@gmail.com>
use strict;

package Bugzilla::Extension::AssigneeList::Group;

use base qw(Bugzilla::Object);

use Bugzilla::Error;
use Bugzilla::Util;
use Scalar::Util qw(blessed);

use Bugzilla::Extension::AssigneeList::Constants;

###############################
####    Initialization     ####
###############################

use constant DB_TABLE => 'componentleadsgroup';
use constant LIST_ORDER => 'sortkey, name';

use constant DB_COLUMNS => qw(
    id
    component_id
    name
    sortkey
);

use constant UPDATE_COLUMNS => qw(
    name
    sortkey
);

#use constant REQUIRED_FIELD_MAP => {
#    component_id => 'component',
#};

use constant VALIDATORS => {
    name          => \&_check_name,
    sortkey	   => \&_check_sortkey,
};

###############################

sub new {
    my ($class, $param) = @_;
    my $dbh = Bugzilla->dbh;

    my $component;
    if (ref $param and !defined $param->{id}) {
        $component = $param->{component};
        my $name = $param->{name};
        if (!defined $component) {
            ThrowCodeError('bad_arg',
                {argument => 'component',
                 function => "${class}::new"});
        }
        if (!defined $name) {
            ThrowCodeError('bad_arg',
                {argument => 'name',
                 function => "${class}::new"});
        }

        my $condition = 'component_id = ? AND name = ?';
        my @values = ($component->id, $name);
        $param = { condition => $condition, values => \@values };
    }

    unshift @_, $param;
    my $group = $class->SUPER::new(@_);
    # Add the component object as attribute only if the component exists.
    $group->{component} = $component if ($group && $component);
    return $group;
}

sub create {
    my $class = shift;
    my $dbh = Bugzilla->dbh;

    $dbh->bz_start_transaction();

    $class->check_required_create_fields(@_);
    my $params = $class->run_create_validators(@_);
    my $component = delete $params->{component};
    $params->{component_id} = $component->id;

    my $group = $class->insert_create_data($params);
    $group->{component} = $component;

    $dbh->bz_commit_transaction();
    return $group;
}

sub remove_from_db_disabled {
    my $self = shift;
    my $dbh = Bugzilla->dbh;

    $dbh->bz_start_transaction();

    $dbh->do('DELETE FROM componentleads WHERE group_id = ?',
             undef, $self->id);

    $dbh->bz_commit_transaction();
}

################################
# Validators
################################

sub _check_name {
    my ($invocant, $name, undef, $params) = @_;
    my $component = blessed($invocant) ? 
    									$invocant->component : $params->{component};

	$name = trim($name);
    $name || ThrowUserError('assigneegroup_label_required');
    if (length($name) > MAX_LABEL_LENGTH) {
        ThrowUserError('assigneegroup_label_too_long', { label => $name });
    }
    
    my $group = new Bugzilla::Extension::AssigneeList::Group({
                                         name => $name, 
                                         component  => $component,
                                    });
    if ($group && (!ref $invocant || $group->id != $invocant->id)) {
        ThrowUserError('assigneegroup_already_exists', {
        							name    => $group->name,
                                    comp  => $component,
                                });
    }

    return $name;
}

sub _check_sortkey {
    my ($invocant, $sortkey) = @_;
    
    $sortkey ||= 0;
    
    detaint_natural($sortkey) 
    || ThrowUserError('assigneegroup_sortkey_invalid', { sortkey => $sortkey });
    return $sortkey;
}

################################
# Accessors
################################

sub component_id { return $_[0]->{'component_id'}; }
sub name                { return $_[0]->{'name'}; }
sub sortkey            { return $_[0]->{'sortkey'}; }

sub component {
    my $self = shift;
    if (!defined $self->{'component'}) {
        require Bugzilla::Component;
        $self->{'component'} = new Bugzilla::Component($self->component_id);
    }
    return $self->{'component'};
}

################################
# Methods
################################

sub set_name { $_[0]->set('name', $_[1]); }
sub set_sortkey { $_[0]->set('sortkey', $_[1]); }

sub assignee_count {
    my $self = shift;
    my $dbh = Bugzilla->dbh;

    if (!defined $self->{'assignee_count'}) {
        $self->{'assignee_count'} = $dbh->selectrow_array(q{
            SELECT COUNT(*) FROM componentleads
            WHERE group_id = ?}, undef, $self->id) || 0;
    }
    return $self->{'assignee_count'};
}

sub assignees {
    my $self = shift;
    my $dbh = Bugzilla->dbh;

    if (!defined $self->{assignees}) {
        my $ids = $dbh->selectcol_arrayref(q{
            SELECT id FROM componentleads AS L
            LEFT JOIN profiles AS P ON P.userid = L.user_id
            WHERE 
            	L.group_id = ? AND
            	P.disabledtext = ''
            ORDER BY L.sortkey}, undef, $self->id);

        require Bugzilla::Extension::AssigneeList::Assignee;
        $self->{assignees} = Bugzilla::Extension::AssigneeList::Assignee->new_from_list($ids);
    }
    return $self->{assignees};
}

###############################

1;
