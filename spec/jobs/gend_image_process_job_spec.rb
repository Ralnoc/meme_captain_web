require 'rails_helper'

require 'support/create_image'
require 'support/gend_image_skip_callbacks'
require 'support/src_image_skip_callbacks'

describe GendImageProcessJob do
  subject(:gend_image_process_job) { GendImageProcessJob.new(gend_image.id) }
  let(:gend_image) { FactoryGirl.create(:gend_image, image: nil) }

  it 'generates the meme image' do
    gend_image_process_job.perform
    gend_image.reload
    expect(gend_image.magick_image_list.columns).to eq(399)
    expect(gend_image.magick_image_list.rows).to eq(399)
  end

  it 'generates a thumbnail' do
    gend_image_process_job.perform
    expect(gend_image.gend_thumb).to_not be_nil
    expect(gend_image.gend_thumb.width).to eq(
      MemeCaptainWeb::Config::THUMB_SIDE
    )
    expect(gend_image.gend_thumb.height).to eq(
      MemeCaptainWeb::Config::THUMB_SIDE
    )
  end

  it 'marks the gend image as finished' do
    expect do
      gend_image_process_job.perform
      gend_image.reload
    end.to change { gend_image.work_in_progress }.from(true).to(false)
  end

  it "enqueues a job to set the gend image's image hash" do
    gend_image_calc_hash_job = instance_double(GendImageCalcHashJob)
    expect(GendImageCalcHashJob).to receive(:new).with(
      gend_image.id
    ).and_return(gend_image_calc_hash_job)
    expect(gend_image_calc_hash_job).to receive(:delay).with(
      queue: :calc_hash
    ).and_return(gend_image_calc_hash_job)
    expect(gend_image_calc_hash_job).to receive(:perform)

    gend_image_process_job.perform
  end

  context 'when an image bucket is configured' do
    before do
      stub_const('MemeCaptainWeb::Config::IMAGE_BUCKET', 'test-image-bucket')
    end

    it 'enqueues jobs to move the image and thumbnail to the bucket' do
      image_move_external_job = instance_double(ImageMoveExternalJob)
      expect(ImageMoveExternalJob).to receive(:new).with(
        GendImage, gend_image.id, 'test-image-bucket'
      ).and_return(image_move_external_job)
      expect(image_move_external_job).to receive(:delay).with(
        queue: :move_image_external
      ).and_return(image_move_external_job)
      expect(image_move_external_job).to receive(:perform)

      thumb_move_external_job = instance_double(ImageMoveExternalJob)
      expect(ImageMoveExternalJob).to receive(:new) do |klass, id, bucket|
        expect(klass).to eq(GendThumb)
        gend_image.reload
        expect(id).to eq(gend_image.gend_thumb.id)
        expect(bucket).to eq('test-image-bucket')
        thumb_move_external_job
      end
      expect(thumb_move_external_job).to receive(:delay).with(
        queue: :move_image_external
      ).and_return(thumb_move_external_job)
      expect(thumb_move_external_job).to receive(:perform)

      gend_image_process_job.perform
    end
  end

  context 'when the src image is in an external object store' do
    let(:src_image) do
      FactoryGirl.create(
        :finished_src_image,
        image_external_bucket: 'bucket1',
        image_external_key: 'key1'
      )
    end
    let(:gend_image) do
      FactoryGirl.create(:gend_image, image: nil, src_image: src_image)
    end
    before do
      stub_request(:get, 'https://bucket1.s3.amazonaws.com/key1').to_return(
        body: create_image(37, 73)
      )
      stub_request(
        :get,
        'http://169.254.169.254/latest/meta-data/iam/security-credentials/'
      ).to_return(
        status: 404
      )
      stub_const('ENV', 'AWS_ACCESS_KEY_ID' => 'test',
                        'AWS_SECRET_ACCESS_KEY' => 'test',
                        'AWS_REGION' => 'us-east-1')
    end

    it 'generates the meme image' do
      gend_image_process_job.perform
      gend_image.reload
      expect(gend_image.magick_image_list.columns).to eq(37)
      expect(gend_image.magick_image_list.rows).to eq(73)
    end
  end

  describe '#failure' do
    let(:delayed_job) { instance_double(Delayed::Job) }

    context 'when the job last_error is nil' do
      before { allow(delayed_job).to receive(:last_error).and_return(nil) }

      it 'does not update the gend image error' do
        expect do
          gend_image_process_job.failure(delayed_job)
        end.to_not(change { gend_image.error })
      end
    end

    context 'when the job last_error is empty' do
      before { allow(delayed_job).to receive(:last_error).and_return('') }

      it 'does not update the gend image error' do
        expect do
          gend_image_process_job.failure(delayed_job)
        end.to_not(change { gend_image.error })
      end
    end

    context 'when the job last_error is not blank' do
      before do
        allow(delayed_job).to receive(:last_error).and_return(
          "an error\na traceback"
        )
      end

      it 'updates the error field to the first line of the error' do
        gend_image_process_job.failure(delayed_job)
        gend_image.reload
        expect(gend_image.error).to eq('an error')
      end
    end

    context 'when the job last_error has only one line' do
      before do
        allow(delayed_job).to receive(:last_error).and_return(
          'another error'
        )
      end

      it 'updates the error field to the first line of the error' do
        gend_image_process_job.failure(delayed_job)
        gend_image.reload
        expect(gend_image.error).to eq('another error')
      end
    end
  end

  describe '#reschedule_at' do
    it 'reschedules in 1 second' do
      expect(gend_image_process_job.reschedule_at(123, 0)).to eq(124)
    end
  end

  describe '#max_attempts' do
    it 'is 1' do
      expect(gend_image_process_job.max_attempts).to eq(1)
    end
  end
end
