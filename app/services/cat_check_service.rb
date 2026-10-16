# アップロードされた画像に猫が写っているかを Decisions API で判定する
class CatCheckService < BaseService
  # この確率以上なら猫とみなす
  THRESHOLD = 0.8
  # 受け付ける画像形式
  CONTENT_TYPES = %w(image/png image/jpeg image/webp).freeze
  # アップロードできる最大サイズ
  MAX_IMAGE_SIZE = 10.megabytes
  # 判定条件。本物の猫だけを許容、イラスト・ぬいぐるみ・置物・大型のネコ科は除外する
  INSTRUCTIONS = <<~TEXT.squish
    Is a real cat visible in this image?
    Count it even if only part of the cat is visible.
    Do not count illustrations, toys, or statues of cats.
    Do not count big cats such as tigers or lions.
  TEXT

  # 判定結果。status は :cat / :not_cat / :refused
  Result = Data.define(:status, :probability, :processing_time_ms)

  attr_reader :result, :messages, :error_status

  def initialize(image)
    super()
    @image = image
  end

  # 入力を確認して API を呼び、成功なら true、失敗なら false を返す
  def call
    return false unless valid?

    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    answer = request_cat_detection
    processing_time_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round
    @result = build_result(answer, processing_time_ms)
    return failure('判定結果を正常に取得できませんでした') if @result.nil?

    true
  rescue OpenAI::Errors::APIError => e
    Rails.logger.error(e)
    failure('判定中にエラーが発生しました', :bad_gateway)
  end

  private

  # 画像と API キーを確認する。問題があれば失敗にして false を返す
  def valid?
    return failure('画像を選択してください') if @image.blank?
    return failure('対応していない画像形式です') if CONTENT_TYPES.exclude?(@image.content_type)
    return failure('画像サイズは10MB以下にしてください') if @image.size > MAX_IMAGE_SIZE
    return failure('APIキーが設定されていません', :internal_server_error) if api_key.blank?

    true
  end

  # Decisions API に画像を送り、最初の回答を返す
  def request_cat_detection
    OpenAI::Client.new(api_key:).decisions.create(
      model: 'gpt-6-luna',
      input: [{ role: :user, content: image_content }],
      questions: [{ type: :predicate, name: 'is_cat', instructions: INSTRUCTIONS }]
    ).answers.first
  end

  # 画像を base64 の data URL にして、API に渡すメッセージを作る
  def image_content
    [
      { type: :input_text, text: 'Check the animal in this photo.' },
      { type: :input_image, image_url: "data:#{@image.content_type};base64,#{Base64.strict_encode64(@image.read)}" }
    ]
  end

  # API の回答を Result に変換する。想定外の回答は nil
  def build_result(answer, processing_time_ms)
    case answer
    when OpenAI::Models::Decision::Answer::Predicate
      status = answer.probability >= THRESHOLD ? :cat : :not_cat
      Result.new(status:, probability: answer.probability, processing_time_ms:)
    when OpenAI::Models::Decision::Answer::Refusal
      Result.new(status: :refused, probability: nil, processing_time_ms:)
    end
  end

  # credentials から OpenAI の API キーを読む
  def api_key
    Rails.application.credentials.dig(:openai, :api_key)
  end

  # 画面に出すエラーメッセージと HTTP ステータスをセットして失敗を返す
  def failure(message, status = :unprocessable_content)
    @messages = message
    @error_status = status
    false
  end
end
