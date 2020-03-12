#!/bin/bash
#
#VARIABLES
LDAP_SERVER="ldap.EXAMPLE.COM"
LDAP_ADMIN="cn=admin,dc=EXAMPLE,dc=COM"
LDAP_PASSWORD="XXX"
PEOPLE_DN="ou=people,dc=EXAMPLE,dc=COM"
VCS_DN="ou=vcs,dc=EXAMPLE,dc=COM"
GROUP_DN="ou=posixGroup,dc=EXAMPLE,dc=COM"
LDAP_GROUPS="ou=groups,dc=EXAMPLE,dc=COM"
CHECK_LAST_UID=$(ldapsearch -h $LDAP_SERVER -D $LDAP_ADMIN -w $LDAP_PASSWORD -b $PEOPLE_DN -S uidNumber | grep uidNumber | awk -F' ' '{print $2;}' | tail -n 1)
ADD_LDAP_LDIF="ldapadd -h $LDAP_SERVER -D $LDAP_ADMIN -w $LDAP_PASSWORD"
LIST_LDAP_GROUPS=$(ldapsearch -h $LDAP_SERVER -D $LDAP_ADMIN -w $LDAP_PASSWORD -b $LDAP_GROUPS | sort | grep cn: | awk -F' ' '{print $2;}')
LIST_LDAP_USERS=$(ldapsearch -h $LDAP_SERVER -D $LDAP_ADMIN -w $LDAP_PASSWORD -b $PEOPLE_DN | sort | grep uid: | awk -F' ' '{print $2;}')
LDAP_MODIFY="ldapmodify -h $LDAP_SERVER -D $LDAP_ADMIN -w $LDAP_PASSWORD"
#----------------------------------------------------------------------------------------------------------------------------------------------------



#----------------------------------------------------------------------------------------------------------------------------------------------------
createUser () {
    echo -n "Enter uid: "
    read LDAP_USER
    while ldapsearch -h $LDAP_SERVER -D $LDAP_ADMIN -w $LDAP_PASSWORD -b uid="$LDAP_USER",$PEOPLE_DN 2&> /dev/null
    do
        echo "Your uid already taken, please write another: "
        echo -n "Enter uid: "
        read LDAP_USER
    done

    echo -n "Enter real name of user: "
    read NAME

    echo -n "Enter surname name of user: "
    read SURNAME

    echo -n "Enter e-mail: "
    read EMAIL

    echo ''
    echo ''

    PASSWD=$(pwgen 24 1 -s -B)
    VCS_PASSWD=$(pwgen 24 1 -s -B)
    echo "PEOPLE: $PASSWD"
    echo "VCS: $VCS_PASSWD"

    echo ''
    echo ''

    ssha_passwd() {
        local salt="$(openssl rand -base64 3)"
        local ssha_pass=$(printf "${PASSWD}${salt}" |openssl dgst -binary -sha1 |sed 's#$#'"${salt}"'#' |base64);
        echo "{SSHA}$ssha_pass"
    }
    ssha_p=$(ssha_passwd q)

    ssha_vcs_passwd() {
        local salt="$(openssl rand -base64 3)"
        local ssha_vcs_pass=$(printf "${VCS_PASSWD}${salt}" |openssl dgst -binary -sha1 |sed 's#$#'"${salt}"'#' |base64);
        echo "{SSHA}$ssha_vcs_pass"
    }
    ssha_v=$(ssha_vcs_passwd q)

    _UID=$(($CHECK_LAST_UID + 1))
    _GID=$_UID

    # LDIF ADD USER GROUP

    LDIF_USER_GROUP=(
        "dn: cn=$LDAP_USER,$GROUP_DN"
        "objectClass: posixGroup"
        "gidNumber: $_GID"
        "description: posixGroup account"
    )

    printf '%s\n' "${LDIF_USER_GROUP[@]}" > ldif_user_group.template
    $ADD_LDAP_LDIF -f ldif_user_group.template

    # LDIF PEOPLE TEMPLATE

    LDIF_PEOPLE=(
        "dn: uid=$LDAP_USER,$PEOPLE_DN"
        "objectClass: person"
        "objectClass: organizationalPerson"
        "objectClass: inetOrgPerson"
        "objectClass: shadowAccount"
        "objectClass: posixAccount"
        "objectClass: top"
        "cn: $NAME $SURNAME"
        "gidNumber: $_GID"
        "homeDirectory: /home/$LDAP_USER"
        "sn: $SURNAME"
        "uid: $LDAP_USER"
        "uidNumber: $_UID"
        "givenName: $NAME"
        "loginShell: /bin/bash"
        "mail: $EMAIL"
        "userPassword: $ssha_p"
    )

    printf '%s\n' "${LDIF_PEOPLE[@]}" > ldif_people.template
    $ADD_LDAP_LDIF -f ldif_people.template
  
    # Ldif VCS template ##################################

    LDIF_VCS=(
        "dn: uid=$LDAP_USER,$VCS_DN"
        "objectClass: inetOrgPerson"
        "cn: gitlab"
        "sn: $SURNAME"
        "description: User account"
        "givenName: $NAME $SURNAME"
        "mail: $EMAIL"
        "uid: $LDAP_USER"
        "userPassword: $ssha_v"
    )

    printf '%s\n' "${LDIF_VCS[@]}" > ldif_vcs.template
    $ADD_LDAP_LDIF -f ldif_vcs.template
}   
deleteUser () {
    echo -n "Enter uid user who will be deleted: "
    read LDAP_USER
    until ldapsearch -h $LDAP_SERVER -D $LDAP_ADMIN -w $LDAP_PASSWORD -b uid="$LDAP_USER",$PEOPLE_DN 2&> /dev/null
    do
        echo "User NOT find in LDAP"
        echo -n "Enter valid LDAP account:  "
        read LDAP_USER
    done
        ldapdelete -h $LDAP_SERVER -D $LDAP_ADMIN -w $LDAP_PASSWORD -c uid="$LDAP_USER",$PEOPLE_DN uid="$LDAP_USER",$VCS_DN cn="$LDAP_USER",$GROUP_DN 2&> /dev/null
        echo "User $LDAP_USER has been deleted from LDAP"
}
changePasswd () {
    echo -n "Enter uid user for change password: "
    read LDAP_USER
    until ldapsearch -h $LDAP_SERVER -D $LDAP_ADMIN -w $LDAP_PASSWORD -b uid="$LDAP_USER",$PEOPLE_DN 2&> /dev/null
    do
        echo "User NOT find in LDAP"
        echo -n "Enter valid LDAP account:  "
        read LDAP_USER
    done
    PASSWD=$(pwgen 24 1 -s -B)
    VCS_PASSWD=$(pwgen 24 1 -s -B)

    ldappasswd -h $LDAP_SERVER -D $LDAP_ADMIN -w $LDAP_PASSWORD -s $PASSWD "uid=$LDAP_USER,$PEOPLE_DN"
    ldappasswd -h $LDAP_SERVER -D $LDAP_ADMIN -w $LDAP_PASSWORD -s $VCS_PASSWD "uid=$LDAP_USER,$VCS_DN"

    echo "New passwords for user $LDAP_USER"
    echo ""
    echo "PEOPLE: $PASSWD"
    echo "VCS: $VCS_PASSWD"
    echo ""    
}
addGroup () {
    echo "Now ldap have this groups: "
    echo ""
    echo -e  "$LIST_LDAP_GROUPS"
    echo ""
    echo -n "Enter the name new LDAP Group in lowercase without spaces: "
    read NEWGROUPNAME
    echo -n "Enter your account from LDAP, it will be first member in this group: "
    read FIRST_MEMBER_IN_NEW_GROUP
    until ldapsearch -h $LDAP_SERVER -D $LDAP_ADMIN -w $LDAP_PASSWORD -b uid=$FIRST_MEMBER_IN_NEW_GROUP,$PEOPLE_DN 2&> /dev/null
    do
        echo "User NOT find in LDAP"
        echo -n "Enter your account from LDAP, it will be first member in this group: "
        read FIRST_MEMBER_IN_NEW_GROUP
    done
    echo -n "This group for VCS or PEOPLE users?: "
    read TYPE
    until [[ $TYPE = "VCS" ]] || [[ $TYPE = "PEOPLE" ]]
    do
        echo -n "Please write VCS or PEOPLE: "
        read TYPE
    done
    if [ "$TYPE" == "VCS" ]; then
        LDIF_NEW_GROUP=(
            "dn: cn=$NEWGROUPNAME,$LDAP_GROUPS"
            "objectClass: groupOfNames"
            "cn: $NEWGROUPNAME"
            "member: uid=$FIRST_MEMBER_IN_NEW_GROUP, $VCS_DN"
        )
    else
        LDIF_NEW_GROUP=(
            "dn: cn=$NEWGROUPNAME,$LDAP_GROUPS"
            "objectClass: groupOfNames"
            "cn: $NEWGROUPNAME"
            "member: uid=$FIRST_MEMBER_IN_NEW_GROUP, $PEOPLE_DN"
        )
    fi
    echo "User find in LDAP, group $NEWGROUPNAME has been created"
    printf '%s\n' "${LDIF_NEW_GROUP[@]}" > ldif_new_group.template
    $ADD_LDAP_LDIF -f ldif_new_group.template
}
deleteGroup () {
    echo "Now ldap have this groups: "
    echo ""
    echo -e  "$LIST_LDAP_GROUPS"
    echo ""
    echo -n "Enter the name new LDAP Group which is DELETE: "
    read DELETEGROUPNAME
    until ldapsearch -h $LDAP_SERVER -D $LDAP_ADMIN -w $LDAP_PASSWORD -b "cn=$DELETEGROUPNAME,$LDAP_GROUPS" 2&> /dev/null
    do
        echo "Group $DELETEGROUPNAME NOT find in LDAP"
        echo -n "Enter valid group to delete: "
        read DELETEGROUPNAME
    done
    ldapdelete -h $LDAP_SERVER -D $LDAP_ADMIN -w $LDAP_PASSWORD cn=$DELETEGROUPNAME,$LDAP_GROUPS 2&> /dev/null
    echo "Group $DELETEGROUPNAME has been deleted!"
}
addUserToGroup () {
    echo "Now ldap have this groups: "
    echo ""
    echo -e  "$LIST_LDAP_GROUPS"
    echo ""
    echo -n "Enter the username which will be added to groups: "
    read LDAP_USER
    until ldapsearch -h $LDAP_SERVER -D $LDAP_ADMIN -w $LDAP_PASSWORD -b uid="$LDAP_USER",$PEOPLE_DN 2&> /dev/null
    do
        echo "User NOT find in LDAP"
        echo -n "Enter valid account from LDAP: "
        read LDAP_USER
    done
    echo -n "Enter groups (space separated) in which will added user: "
    read -a listGroups

    for i in ${listGroups[@]}; do
        
        if [ "$i" == "gitlab" ] || [ "$i" == "svn" ]; then
            LDIF_ADD_USER_TO_GROUP=(
                "dn: cn=$i,$LDAP_GROUPS"
                "changetype: modify"
                "add: member"
                "member: uid=$LDAP_USER,$VCS_DN"
                "-"
            )
        else
            LDIF_ADD_USER_TO_GROUP=(
                "dn: cn=$i,$LDAP_GROUPS"
                "changetype: modify"
                "add: member"
                "member: uid=$LDAP_USER,$PEOPLE_DN"
                "-"
            )
        fi
        printf '%s\n' "${LDIF_ADD_USER_TO_GROUP[@]}" > add_user_to_group.template
        $LDAP_MODIFY -f add_user_to_group.template
    done
}
deleteUserFromGroup () {
    echo "Now ldap have this groups: "
    echo ""
    echo -e  "$LIST_LDAP_GROUPS"
    echo ""
    echo -n "Enter the username which will be deleted from groups: "
    read LDAP_USER
    until ldapsearch -h $LDAP_SERVER -D $LDAP_ADMIN -w $LDAP_PASSWORD -b uid="$LDAP_USER",$PEOPLE_DN 2&> /dev/null
    do
        echo "User NOT find in LDAP"
        echo -n "Enter valid account from LDAP: "
        read LDAP_USER
    done
    echo -n "Enter groups (space separated) in which will delete user: "
    read -a listGroups

    for i in ${listGroups[@]}; do
        if [ "$i" == "gitlab" ] || [ "$i" == "svn" ]; then
            LDIF_DELETE_USER_FROM_GROUP=(
                "dn: cn=$i,$LDAP_GROUPS"
                "changetype: modify"
                "delete: member"
                "member: uid=$LDAP_USER,$VCS_DN"
                "-"
            )
        else
            LDIF_DELETE_USER_FROM_GROUP=(
                "dn: cn=$i,$LDAP_GROUPS"
                "changetype: modify"
                "delete: member"
                "member: uid=$LDAP_USER,$PEOPLE_DN"
                "-"
            )
        fi
        printf '%s\n' "${LDIF_DELETE_USER_FROM_GROUP[@]}" > delete_user_from_group.template
        $LDAP_MODIFY -f delete_user_from_group.template
    done
}
listUserGroups () {
    echo ""
    echo -n "Enter uid user to show his membership in groups: "
    read LDAP_USER
    until ldapsearch -h $LDAP_SERVER -D $LDAP_ADMIN -w $LDAP_PASSWORD -b uid="$LDAP_USER",$PEOPLE_DN 2&> /dev/null
    do
        echo "User NOT find in LDAP"
        echo -n "Enter valid account from LDAP: "
        read LDAP_USER
    done
    echo ""
    groupArray=$LIST_LDAP_GROUPS
    for i in ${groupArray[@]}; do
     ldapsearch -h $LDAP_SERVER -D $LDAP_ADMIN -w $LDAP_PASSWORD -b "cn=$i,$LDAP_GROUPS" | grep "member: uid=$LDAP_USER" &> /dev/null
        RESULT=$?
        if [ $RESULT -eq 0 ];
        then 
            echo "$i"
        fi
    done

}
listAll () {
    echo ""
    echo "LDAP Groups: "
    echo ""
    echo -e  "$LIST_LDAP_GROUPS"
    echo ""
    echo "LDAP Users: "
    echo ""
    echo -e  "$LIST_LDAP_USERS"
}
manageMenu () {
	clear
	echo "Welcome to openLDAP manager !"
	echo ""
	echo ""
	echo "   1) Add a new user"
	echo "   2) Delete user"
    echo "   3) Change password for user"
	echo "   4) Add group"
	echo "   5) Delete group"
    echo "   6) Add user to group"
    echo "   7) Delete user from group"
    echo "   8) Show user groups membership"
    echo "   9) List all users and groups"
    echo "    "
	until [[ "$MENU_OPTION" =~ ^[1-9]$ ]]; do
	read -rp "Select an option [1-9]: " MENU_OPTION
	done

	case $MENU_OPTION in
		1)
			createUser
		;;
		2)
			deleteUser
		;;
		3)
			changePasswd
        ;;
        4)
			addGroup
		;;
		5)
			deleteGroup
		;;
		6)
			addUserToGroup
		;;
        7)
            deleteUserFromGroup
        ;;
		8)
			listUserGroups
		;;
        9)
            listAll
		;;
	esac
}

manageMenu
