# frozen_string_literal: true
require_relative "../../lib/event"
require "openai"
include Event

class ItemsController < ApplicationController
  before_action :authenticate_user!, except: %i[index show]

  def index
    @items = Item.includes(:tags)

    @items = @items.tagged_with(params[:tag]) if params[:tag].present?
    @items = @items.sellered_by(params[:seller]) if params[:seller].present?
    @items = @items.favorited_by(params[:favorited]) if params[:favorited].present?

    @items_count = @items.count

    @items = @items.order(created_at: :desc).offset(params[:offset] || 0).limit(params[:limit] || 100)

    render json: {
      items: @items.map { |item|
        {
          title: item.title,
          slug: item.slug,
          description: item.description,
          image: item.image,
          tagList: item.tags.map(&:name),
          createdAt: item.created_at,
          updatedAt: item.updated_at,
          seller: {
            username: item.user.username,
            bio: item.user.bio,
            image: item.user.image || 'https://static.productionready.io/images/smiley-cyrus.jpg',
            following: signed_in? ? current_user.following?(item.user) : false,
          },
          favorited: signed_in? ? current_user.favorited?(item) : false,
          favoritesCount: item.favorites_count || 0
        }
      },
      items_count: @items_count
    }
  end

  def feed
    @items = Item.includes(:user).where(user: current_user.following_users)

    @items_count = @items.count

    @items = @items.order(created_at: :asc).offset(params[:offset] || 0).limit(params[:limit] || 20)

    render :index
  end

  def create
    client = OpenAI::Client.new(access_token: "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")
    response = client.images.generate(parameters: { prompt: "A baby sea otter cooking pasta wearing a hat of some sort", size: "256x256" })
    @item = Item.new(item_params)
    @item.user = current_user
    if @item.image.blank?
      @item.image = response.dig("data", 0, "url")
      @item.save!
    end
    byebug
    if @item.save
      sendEvent("item_created", { item: item_params })
      render :show
    else
      render json: { errors: @item.errors }, status: :unprocessable_entity
    end
  end

  def show
    @item = Item.find_by!(slug: params[:slug])
  end

  def update
    @item = Item.find_by!(slug: params[:slug])

    if @item.user_id == @current_user_id
      @item.update(item_params)

      render :show
    else
      render json: { errors: { item: ['not owned by user'] } }, status: :forbidden
    end
  end

  def destroy
    @item = Item.find_by!(slug: params[:slug])

    if @item.user_id == @current_user_id
      @item.destroy

      render json: {}
    else
      render json: { errors: { item: ['not owned by user'] } }, status: :forbidden
    end
  end

  private

  def item_params
    params.require(:item).permit(:title, :description, :image, tag_list: [])
  end
end
