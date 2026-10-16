class CatChecksController < ApplicationController
  def new; end

  def create
    service = CatCheckService.new(image_params[:image])
    if service.call
      @result = service.result
      render :new
    else
      flash.now[:alert] = service.messages
      render :new, status: service.error_status
    end
  end

  private

  def image_params
    params.permit(:image)
  end
end
