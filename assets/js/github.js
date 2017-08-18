---
---
/*
TODO: Check access_token for validity with any authed action (new thread, new post, follow, watch, etc.)
https://developer.github.com/v3/oauth_authorizations/#check-an-authorization
^ Could do simple HTTP code check for 403 Forbidden / 401 Unauthorized instead to avoid client_secret via another middleman URL
  - data.status (401) and data.statusText ("Unauthorized")

Get "member" count: https://developer.github.com/v3/activity/starring/#list-stargazers
Make "member": https://developer.github.com/v3/activity/starring/#star-a-repository

Check if "thread" is watched: https://developer.github.com/v3/activity/watching/#get-a-repository-subscription
Watch a "thread": https://developer.github.com/v3/activity/watching/#set-a-repository-subscription
Unwatch a "thread": https://developer.github.com/v3/activity/watching/#delete-a-repository-subscription
List watched "threads": https://developer.github.com/v3/activity/watching/#list-repositories-being-watched

Notifications: https://developer.github.com/v3/activity/notifications/
*/

var clientId = "{% if site.url == 'http://localhost:4000' %}c0e80cead4650c080812{% else %}{{ site.client_id }}{% endif %}";
var gatekeeperUrl = "https://umod-gatekeeper{% if site.url == 'http://localhost:4000' %}-test{% endif %}.herokuapp.com/authenticate/";
var accessToken = localStorage.getItem("accessToken");

function setAccess() {
    if (getParameter('code') != null) {
        $.ajax({
            url: gatekeeperUrl + getParameter('code'),
            type: 'GET',
            dataType: 'json',
            success: function (data) {
                if (data.error === 'bad_code') {
                    checkAccess();
                } else {
                    localStorage.setItem('accessToken', data.token);
                    window.location = '{{ site.url }}' + window.location.pathname;
                    return true;
                }
            },
            error: function (err) {
                alert("Error: " + JSON.stringify(err));
                return false;
            }
        });
    }
}

function checkAccess() { // TODO: Might need to add a callback
    if (accessToken == null || accessToken === undefined) {
        if (getParameter('code') == null) {
            var scopes = 'public_repo,user:follow';
            var baseUrl = 'https://github.com/login/oauth/authorize';
            var redirectUrl = '{{ site.url }}' + window.location.pathname;
            window.location = baseUrl + '?client_id=' + clientId + '&scope=' + scopes + '&redirect_uri=' + redirectUrl;
        } else {
            return setAccess(); // TODO: Fix this returning undefined sometimes
        }
    } else {
        return true;
    }
}

function createIssue(repo, form) {
    if (!checkAccess()) { return; };
    
    $.ajax({
        url: 'https://api.github.com/repos/' + repo + '/issues',
        type: 'POST',
        data: JSON.stringify({ "title": form[0].value, "body": form[1].value }),
        dataType: 'json',
        contentType: 'application/json',
        beforeSend: function(xhr) {
            xhr.setRequestHeader("Authorization", "token " + accessToken);
        },
        success: function(data) {
            window.location = '{{ site.url }}' + window.location.pathname + '/' + data.number;
            document.title = '{{ site.title }} - ' + data.title;
        },
        error: function(err) {
            alert('Error: ' + JSON.stringify(err));
            // TODO: Show better message
        }
    });
}

function randomString(length) {
    var result = '';
    var chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    for (var i = length; i > 0; --i) result += chars[Math.floor(Math.random() * chars.length)];
    return result;
}

function getParameter(param) {
    if (!param) {
        return window.location.hash.substring(1);
    } else {
        var url = decodeURIComponent(window.location.search.substring(1)), params = url.split('&'), parameter, i;
        for (i = 0; i < params.length; i++) {
            parameter = params[i].split('=');
            if (parameter[0] === param) {
                return parameter[1] === undefined ? true : parameter[1];
            }
        }
    }
}
