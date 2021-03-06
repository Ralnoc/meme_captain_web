require 'rails_helper'

describe ImageMoveExternalJob do
  subject(:image_move_external_job) do
    ImageMoveExternalJob.new(GendImage, gend_image.id, 'test-image-bucket')
  end

  let(:gend_image) { FactoryGirl.create(:gend_image) }

  before do
    expect(GendImage).to receive(:find).with(gend_image.id).and_return(
      gend_image
    )
  end

  it 'moves the image to external storage' do
    expect(gend_image).to receive(:move_image_external).with(
      'test-image-bucket'
    )
    image_move_external_job.perform
  end
end
