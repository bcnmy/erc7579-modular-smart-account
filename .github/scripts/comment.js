module.exports = async ({ github, context, header, body }) => {
  const uniqueSlitherHeader = "# Slither report";

  // Function to select emoji based on the impact level found in the text
  const getEmoji = (text) => {
    if (text.includes("High")) return ":red_circle:";
    if (text.includes("Medium")) return ":yellow_circle:";
    if (text.includes("Low")) return ":large_blue_circle:";
    if (text.includes("Informational")) return ":information_source:";
    return "";
  };

  // Function to shorten GitHub URLs to Markdown link format
  const shortenUrls = (text) => {
    const urlRegex =
      /https:\/\/github\.com\/([\w-]+\/[\w-]+)\/blob\/([a-z0-9]+)\/(.+?)(#L\d+(-L\d+)?)/g;
    return text.replace(urlRegex, (_, repo, commit, path, hash) => {
      const shortPath = path.replace(/^contracts\/contracts\//, "");
      return `[${shortPath}${hash}](https://github.com/${repo}/blob/${commit}/${path}${hash})`;
    });
  };

  // Process the body to add emojis and shorten URLs
  const processedBody = body
    .split("\n")
    .map((line) => {
      let processedLine = shortenUrls(line); // Apply URL shortening
      const emoji = getEmoji(processedLine);
      return emoji ? `${emoji} ${processedLine}` : processedLine;
    })
    .join("\n");

  const markdownComment = `
## :robot: Slither Analysis Report :mag_right:
<details>

${uniqueSlitherHeader}

${header}

${processedBody}

_This comment was automatically generated by the GitHub Actions workflow._
</details>
`;

  // Check if the workflow is triggered by a pull request event
  if (!context.payload.pull_request) {
    console.log(
      "This workflow is not triggered by a pull request. Skipping comment creation/update.",
    );
    return;
  }

  const { data: comments } = await github.rest.issues.listComments({
    owner: context.repo.owner,
    repo: context.repo.repo,
    issue_number: context.payload.pull_request.number,
  });

  // Delete all Slither comments before posting a new one
  for (const comment of comments.filter(
    (comment) =>
      comment.user.type === "Bot" && comment.body.includes(uniqueSlitherHeader),
  )) {
    await github.rest.issues.deleteComment({
      owner: context.repo.owner,
      repo: context.repo.repo,
      comment_id: comment.id,
    });
  }

  // After deleting, post a new comment
  const response = await github.rest.issues.createComment({
    owner: context.repo.owner,
    repo: context.repo.repo,
    issue_number: context.payload.pull_request.number,
    body: markdownComment,
  });

  console.log(
    response.status === 200
      ? "Slither analysis comment created or updated successfully."
      : "Failed to create or update the comment.",
  );
};
