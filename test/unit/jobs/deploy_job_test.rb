require 'test_helper'

class DeployJobTest < ActiveSupport::TestCase

  setup do
    @job = DeployJob.new
    @deploy = deploys(:shipit_pending)
    @stack = stacks(:shipit)
  end

  test "#perform fetch commits from the API" do
    @job.stubs(:capture)
    @commands = stub(:commands)
    Deploy.expects(:find).with(@deploy.id).returns(@deploy)
    DeployCommands.expects(:new).with(@deploy).returns(@commands)

    @commands.expects(:fetch).once
    @commands.expects(:clone).once
    @commands.expects(:checkout).with(@deploy.until_commit).once
    @commands.expects(:install_dependencies).returns([]).once
    @commands.expects(:deploy).with(@deploy.until_commit).returns([]).once

    @deploy.expects(:clear_working_directory)

    @job.perform(deploy_id: @deploy.id)
  end

  test "#perform enqueues a FetchDeployedRevisionJob" do
    Dir.stubs(:chdir).yields
    DeployCommands.any_instance.stubs(:deploy).returns([])
    @job.stubs(:capture)

    Resque.expects(:enqueue).with(FetchDeployedRevisionJob, stack_id: @deploy.stack_id)
    @job.perform(deploy_id: @deploy.id)
  end

  test "marks deploy as successful" do
    Dir.stubs(:chdir).yields
    DeployCommands.any_instance.stubs(:deploy).returns([])
    @job.stubs(:capture)

    @job.perform(deploy_id: @deploy.id)
    assert_equal 'success', @deploy.reload.status
  end

  test "marks deploy as `error` if any application error is raised" do
    @job.expects(:capture).raises("some error")
    assert_raise(RuntimeError) do
      @job.perform(deploy_id: @deploy.id)
    end
    assert_equal 'error', @deploy.reload.status
  end

  test "marks deploy as `failed` if a command exit with an error code" do
    @job.expects(:capture).raises(Command::Error.new('something'))
    @job.perform(deploy_id: @deploy.id)
    assert_equal 'failed', @deploy.reload.status
  end

  test "bail out if deploy is not pending" do
    @deploy.run!
    @job.expects(:capture).never
    @job.perform(deploy_id: @deploy.id)
  end

  test "mark deploy as error if a command timeout" do
    Timeout.expects(:timeout).raises(Timeout::Error.new)
    Command.any_instance.expects(:terminate!)
    assert_raises(Timeout::Error) do
      @job.perform(deploy_id: @deploy.id)
    end
    assert @deploy.reload.error?
  end

  test "records stack support for rollbacks and fetching deployed revision" do
    @job.stubs(:capture)
    @commands = stub(:commands)
    @commands.stubs(:fetch).returns([])
    @commands.stubs(:clone).returns([])
    @commands.stubs(:checkout).returns([])
    @commands.stubs(:install_dependencies).returns([])
    @commands.stubs(:deploy).returns([])
    Deploy.expects(:find).with(@deploy.id).returns(@deploy)
    DeployCommands.expects(:new).with(@deploy).returns(@commands)
    @deploy.stubs(:clear_working_directory)

    DeploySpec.any_instance.expects(:supports_fetch_deployed_revision?).returns(true)
    DeploySpec.any_instance.expects(:supports_rollback?).returns(true)

    @stack.update!(supports_rollback: false, supports_fetch_deployed_revision: false)

    refute @stack.supports_rollback?
    refute @stack.supports_fetch_deployed_revision?

    @job.perform(deploy_id: @deploy.id)
    @stack.reload

    assert @stack.supports_rollback?
    assert @stack.supports_fetch_deployed_revision?
  end

end
