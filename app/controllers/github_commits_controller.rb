class GithubCommitsController < ApplicationController

  unloadable

  skip_before_action :check_if_login_required
  skip_before_action :verify_authenticity_token

  TIMELOG_RE = /
    (
    ((\d+)(h|hours?))((\d+)(m|min)?)?
    |
    ((\d+)(h|hours?|m|min))
    |
    (\d+):(\d+)
    |
    (\d+([\.,]\d+)?)h?
    )
    /x
  def create_comment
    resp_json = nil
    if params[:commits].present?

      repository_name = params[:repository][:name]
      branch = params[:ref].split("/").last

      params[:commits].each do |last_commit|
        comments = last_commit[:message]
        email = EmailAddress.find_by(address: last_commit[:author][:email])
        user = email.present? ? email.user : User.where(admin: true).first

        ref_keywords = Setting.commit_ref_keywords.downcase.split(",").collect(&:strip)
        ref_keywords_any = ref_keywords.delete('*')

        # keywords used to fix issues
        fix_keywords = Setting.commit_update_keywords_array.map {|r| r['keywords']}.flatten.compact
        kw_regexp = (ref_keywords + fix_keywords).collect{|kw| Regexp.escape(kw)}.join("|")

        referenced_issues = []
        regexp =
          %r{
            ([\s\(\[,-]|^)((#{kw_regexp})[\s:]+)?
            (\#\d+(\s+@#{TIMELOG_RE})?([\s,;&]+\#\d+(\s+@#{TIMELOG_RE})?)*)
            (?=[[:punct:]]|\s|<|$)
          }xi
        comments.scan(regexp) do |match|
          action = match[2].to_s.downcase
          refs   = match[3]
          next unless action.present? || ref_keywords_any

          refs.scan(/#(\d+)(\s+@#{TIMELOG_RE})?/).each do |m|
            issue = find_referenced_issue_by_id(m[0].to_i)
            hours = m[2]
            if issue
              referenced_issues << issue
              # Don't update issues or log time when importing old commits
              text_tag ="#{issue.project.identifier}:commit:#{repository_name}:#{last_commit[:id]}"
              commit_date = Date.parse(last_commit[:timestamp])
              fix_issue(user,issue, action,last_commit) if fix_keywords.include?(action)
              log_time(user,issue, hours,text_tag,commit_date) if hours && Setting.commit_logtime_enabled?
            end
          end
        end

        resp_json = {success: true}
      end

    else
      resp_json = {success: false, error: t('lables.no_commit_data_found') }
    end
    render json: resp_json,status: 200

  end

  def find_referenced_issue_by_id(id)
    return nil if id.blank?

    issue = Issue.find_by_id(id.to_i)
    if Setting.commit_cross_project_ref?

    elsif issue
      unless issue.project &&
                (project == issue.project || project.is_ancestor_of?(issue.project) ||
                 project.is_descendant_of?(issue.project))
        issue = nil
      end
    end
    issue
  end


  # Updates the +issue+ according to +action+
  def fix_issue(user,issue, action,text_tag)
    # the issue may have been updated by the closure of another one (eg. duplicate)
    issue.reload
    # don't change the status is the issue is closed
    return if issue.closed?

    journal = issue.init_journal(user || User.anonymous,
                                 ll(Setting.default_language,
                                    :text_status_changed_by_changeset,
                                    text_tag))
    rule = Setting.commit_update_keywords_array.detect do |rule|
      rule['keywords'].include?(action) &&
        (rule['if_tracker_id'].blank? || rule['if_tracker_id'] == issue.tracker_id.to_s)
    end
    if rule
      issue.assign_attributes rule.slice(*Issue.attribute_names)
    end
    Redmine::Hook.call_hook(:model_changeset_scan_commit_for_issue_ids_pre_issue_update,
                            {:changeset => self, :issue => issue, :action => action})

    if issue.changes.any?
      unless issue.save
        logger.warn("Issue ##{issue.id} could not be saved by changeset #{id}: #{issue.errors.full_messages}") if logger
      end
    else
      issue.clear_journal
    end
    issue
  end

  def log_time(user,issue, hours,text_tag,commit_date)
    time_entry =
      TimeEntry.new(
        :user => user,
        :hours => hours,
        :issue => issue,
        :spent_on => commit_date,
        :comments => l(:text_time_logged_by_changeset, :value => text_tag,
                       :locale => Setting.default_language)
      )
    if activity = issue.project.commit_logtime_activity
      time_entry.activity = activity
    end

    unless time_entry.save
      logger.warn("TimeEntry could not be created by changeset #{issue.id}: #{time_entry.errors.full_messages}") if logger
    end
    time_entry
  end
end
