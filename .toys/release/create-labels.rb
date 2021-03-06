# frozen_string_literal: true

desc "Create GitHub labels for releases"

long_desc \
  "This tool ensures that the proper GitHub labels are present for the" \
    " release automation scripts."

flag :yes, "--yes", "-y" do
  desc "Automatically answer yes to all confirmations"
end

include :exec, exit_on_nonzero_status: true
include :terminal, styled: true

def run
  require "release_utils"
  require "json"
  require "cgi"
  utils = ReleaseUtils.new self

  expected_labels = create_expected_labels utils
  cur_labels = load_existing_labels utils.repo_path
  update_labels cur_labels, expected_labels, utils.repo_path
end

def create_expected_labels utils
  [
    {
      "name"        => utils.release_pending_label,
      "color"       => "ddeeff",
      "description" => "Automated release is pending"
    },
    {
      "name"        => utils.release_error_label,
      "color"       => "ffdddd",
      "description" => "Automated release failed with an error"
    },
    {
      "name"        => utils.release_aborted_label,
      "color"       => "eeeeee",
      "description" => "Automated release was aborted"
    },
    {
      "name"        => utils.release_complete_label,
      "color"       => "ddffdd",
      "description" => "Automated release completed successfully"
    }
  ]
end

def load_existing_labels repo_path
  output = capture ["gh", "api", "repos/#{repo_path}/labels",
                    "-H", "Accept: application/vnd.github.v3+json"]
  ::JSON.parse output
end

def update_labels cur_labels, expected_labels, repo_path
  expected_labels.each do |expected|
    cur = cur_labels.find { |label| label["name"] == expected["name"] }
    if cur
      if cur["color"] != expected["color"] || cur["description"] != expected["description"]
        update_label expected, repo_path
      end
    else
      create_label expected, repo_path
    end
  end
  cur_labels.each do |cur|
    next unless cur["name"].start_with? "release: "
    expected = expected_labels.find { |label| label["name"] == cur["name"] }
    delete_label cur, repo_path unless expected
  end
end

def create_label label, repo_path
  label_name = label["name"]
  return unless yes || confirm("Label \"#{label_name}\" doesn't exist. Create? ", default: true)
  body = ::JSON.dump label
  exec ["gh", "api", "repos/#{repo_path}/labels", "--input", "-",
        "-H", "Accept: application/vnd.github.v3+json"],
       in: [:string, body], out: :null
end

def update_label label, repo_path
  label_name = label["name"]
  return unless yes || confirm("Update fields of \"#{label_name}\"? ", default: true)
  body = ::JSON.dump color: label["color"], description: label["description"]
  exec ["gh", "api", "-XPATCH", ::CGI.escape("repos/#{repo_path}/labels/#{label_name}"),
        "--input", "-", "-H", "Accept: application/vnd.github.v3+json"],
       in: [:string, body], out: :null
end

def delete_label label, repo_path
  label_name = label["name"]
  return unless yes || confirm("Label \"#{label_name}\" unrecognized. Delete? ", default: true)
  exec ["gh", "api", "-XDELETE", ::CGI.escape("repos/#{repo_path}/labels/#{label_name}"),
        "-H", "Accept: application/vnd.github.v3+json"],
       out: :null
end
