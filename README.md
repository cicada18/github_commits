# github_commits by cicada18
This plugin adds a comment in redmine issue whenever user commits to github with the redmine issue number in the commit message. We have created this plugin because it is very painful to keep track of all commits for an issue, and we just wanted to connect the github with our own Redmine. 

This plugins follow Github hook.

tested on redmine 4.2.*

## Steps to use this plugin:

1.  Go to the repository Settings interface on GitHub.
2.  Under "Webhooks & Services" add a new "WebHook". The "Payload URL" needs to be of the format:
    [redmine_url]/github_commits/create_comment (for example http://redmine.example.com/github_commits/create_comment).
3.  When user commits on github, the commit message should include `#123` where `123` should be the issue_id in redmine for which the commit is pushed. for eg : `git commit -m 'ok:#211 @2h test commit'`, setting in /settings?tab=repositories:
    ok: Tracker
    #211: Referencing keywords
    @2h:  Enable time logging(checked)
    

4. User who pushes commit on github, should have the same email address which is used as redmine user also. It will add comment on behalf of the original user or admin user.
