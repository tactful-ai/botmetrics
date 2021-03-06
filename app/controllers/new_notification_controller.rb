class NewNotificationController < ApplicationController
  before_action :authenticate_user!
  before_action :find_bot

  before_action :reset_session!, only: [:step_1]
  before_action :validate_step_1!, only: [:step_2]
  before_action :validate_step_2!, only: [:step_3]

  helper_method :default_query

  layout 'app'

  def step_1
    @query_set =
      QuerySetBuilder.new(
        bot: @bot,
        instances_scope: :enabled,
        time_zone: current_user.timezone,
        default: default_query,
        params: params,
        session: session[:new_notification_query_set]
      ).query_set

    @tableized = FilterBotUsersService.new(@query_set).scope.page(params[:page])

    session[:new_notification_query_set] = @query_set.to_form_params
  end

  def step_2
    @notification = @bot.notifications.build(model_params)
  end

  def step_3
    @notification = @bot.notifications.build(model_params)
  end

  def create
    @query_set    = QuerySetBuilder.new(session: session[:new_notification_query_set]).query_set
    @notification = @bot.notifications.build(model_params.merge(query_set: @query_set))

    if @query_set.present? && @query_set.valid? && @notification.save(context: :schedule)
      session.delete(:new_notification_query_set)

      send_or_queue_and_redirect
    else
      if (error = @notification.errors[:scheduled_at]).present?
        flash[:error] = "The time you picked has already passed in some time zones"
      end

      redirect_to step_3_bot_new_notification_index_path(@bot, params.slice(:notification))
    end
  end

  private
  def default_query
    { provider: @bot.provider, field: :interaction_count, method: :greater_than, value: 1 }
  end

  def model_params
    if params[:notification].present?
      params.require(:notification).permit(:content, :scheduled_at, :recurring)
    else
      Hash.new
    end
  end

  def reset_session!
    if params[:reset].present? || action_name == 'step_1'
      session.delete(:new_notification_query_set)
    end
  end

  def validate_step_1!
    if session[:new_notification_query_set].blank?
      redirect_to step_1_bot_new_notification_index_path(@bot) and return
    end
  end

  def validate_step_2!
    if params.dig(:notification, :content).blank?
      redirect_to step_2_bot_new_notification_index_path(@bot, params.slice(:notification)) and return
    end
  end

  def send_or_queue_and_redirect
    if @notification.send_immediately?
      SendNotificationJob.perform_async(@notification.id)
      redirect_to [@bot, @notification]
    else
      EnqueueNotificationJob.perform_async(@notification.id)
      redirect_to bot_notifications_path(@bot), notice: 'This notification has been queued.'
    end
  end
end
