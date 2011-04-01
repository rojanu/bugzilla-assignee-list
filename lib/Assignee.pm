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

package Bugzilla::Extension::AssigneeList::Assignee;

use base qw(Bugzilla::Object);

use Bugzilla::Error;
use Bugzilla::Util;
use Scalar::Util qw(blessed);

use Bugzilla::Extension::AssigneeList::Constants;

###############################
####    Initialization     ####
###############################

use constant DB_TABLE => 'componentleads';
use constant LIST_ORDER => ' group_id,sortkey';

use constant DB_COLUMNS => qw(
    id
    user_id
    group_id
    name
    sortkey
);

use constant UPDATE_COLUMNS => qw(
    group_id
    name
    sortkey
);

use constant VALIDATORS => {
    group     => \&_check_group,
    name     => \&_check_name,
    sortkey   => \&_check_sortkey,
    user        => \&_check_user,
};

###############################

sub new {
    my ($class, $param) = @_;
    my $dbh = Bugzilla->dbh;

    my $group;
    my $user;
    if (ref $param and !defined $param->{id}) {
        $group = $param->{group};
        $user = $param->{user};
        my $name = $param->{name};
        if (!defined $group) {
            ThrowCodeError('bad_arg',
                {argument => 'group',
                 function => "${class}::new"});
        }
        if (!defined $user) {
            ThrowCodeError('bad_arg',
                {argument => 'user',
                 function => "${class}::new"});
        }
        if (!defined $name) {
            ThrowCodeError('bad_arg',
                {argument => 'name',
                 function => "${class}::new"});
        }

        my $condition = 'group_id = ? AND user_id =? AND name = ?';
        my @values = ($group->id, $user->id, $name);
        $param = { condition => $condition, values => \@values };
    }

    unshift @_, $param;
    my $assignee = $class->SUPER::new(@_);
    # Add the group object as attribute only if the group exists.
    $assignee->{group} = $group if ($assignee && $group);
    # Add the user object as attribute only if the user exists.
    $assignee->{user} = $user if ($assignee && $user);
    return $assignee;
}

sub create {
    my $class = shift;
    my $dbh = Bugzilla->dbh;

    $dbh->bz_start_transaction();

    $class->check_required_create_fields(@_);
    my $params = $class->run_create_validators(@_);
    my $group = delete $params->{group};
    $params->{group_id} = $group->id;

    my $user = delete $params->{user};
    $params->{user_id} = $user->id;

    my $assignee = $class->insert_create_data($params);
    $assignee->{group} = $group;
    $assignee->{user} = $user;

    $dbh->bz_commit_transaction();
    return $assignee;
}

################################
# Validators
################################

sub _check_name {
    my ($class, $value) = @_;

    if (!$value) {
        ThrowUserError('assignee_label_required');
    }

    if (length($value) > MAX_LABEL_LENGTH) {
        ThrowUserError('assignee_label_too_long', { label => $value });
    }

    return $value;
}

sub _check_sortkey {
    my ($invocant, $sortkey) = @_;
    
    $sortkey ||= 0;
    
    detaint_natural($sortkey) 
    || ThrowUserError('assignee_sortkey_invalid', { sortkey => $sortkey });
    return $sortkey;
}

sub _check_group {
    my ($invocant, $group) = @_;
    $group || ThrowCodeError('param_required', 
                    { function => "$invocant->create", param => 'group' });
	require Bugzilla::Extension::AssigneeList::Group;
    return new Bugzilla::Extension::AssigneeList::Group($group->id);
}

sub _check_user {
    my ($invocant, $user) = @_;
    $user || ThrowCodeError('param_required', 
                    { function => "$invocant->create", param => 'user' });
	require Bugzilla::User;
    return new Bugzilla::User($user->id);
}

################################
# Methods
################################

sub set_name { $_[0]->set('name', $_[1]); }
sub set_sortkey { $_[0]->set('sortkey', $_[1]); }

sub set_group {
    my ($self, $group) = @_;
	$self->set('group_id', $group->id);
    $self->{'group'} = $group;
}

################################
# Accessors
################################

sub user_id            { return $_[0]->{'user_id'}; }
sub group_id          { return $_[0]->{'group_id'}; }
sub name                { return $_[0]->{'name'}; }
sub sortkey            { return $_[0]->{'sortkey'}; }

sub group {
    my $self = shift;
    if (!defined $self->{'group'}) {
        require Bugzilla::Extension::AssigneeList::Group;
        $self->{'group'} = new Bugzilla::Extension::AssigneeList::Group($self->group_id);
    }
    return $self->{'group'};
}

sub user {
    my $self = shift;
    if (!defined $self->{'user'}) {
        require Bugzilla::User;
        $self->{'user'} = new Bugzilla::User($self->user_id);
    }
    return $self->{'user'};
}

###############################

1;
